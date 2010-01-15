package Data::ObjectMapper::Mapper::Instance;
use strict;
use warnings;
use Carp::Clan;
use Scalar::Util qw(refaddr weaken);
use Log::Any qw($log);
use Data::ObjectMapper::Utils;

my %INSTANCES;
my %STATUS = (
    # "status" => "changable status"
    transient  => [ 'pending', 'persistent' ],
    pending    => ['expired'],
    persistent => ['expired', 'detached'],
    detached   => [],
    expired    => ['persistent'],
);

sub new {
    my ( $class, $instance ) = @_;
    return $class->get($instance) || $class->create($instance);
}

sub create {
    my ( $class, $instance ) = @_;

    my $self = bless {
        instance           => $instance,
        status             => 'transient',
        is_modified        => 0,
        modified_data      => +{},
        unit_of_work       => undef,
        identity_condition => undef,
    }, $class;
    $INSTANCES{refaddr($instance)} = $self;
    $self->init_identity_condition;
    return $self;
}

sub instances { %INSTANCES }

sub init_identity_condition {
    my $self = shift;
    my $record = shift || $self->reducing;
    my $class_mapper = $self->instance->__class_mapper__;
    my $identity_condition
        = +[ map { $class_mapper->table->c($_) == $record->{$_} }
            @{ $class_mapper->table->primary_key } ];

    if( @$identity_condition ) {
        return $self->{identity_condition} = $identity_condition;
    }
    elsif( my $unique_key = @{ $class_mapper->table->unique_key } ) {
        for my $uniq ( @$unique_key ) {
            return $self->{identity_condition} = map {
                $class_mapper->table->c($_) == $record->{$_} } @{$uniq->[1]};
        }
    }

    confess "Can't define identity.";
}

sub identity_condition { $_[0]->{identity_condition} }

sub get {
    my ( $self, $instance ) = @_;
    $INSTANCES{refaddr($instance)};
}

sub unit_of_work       { $_[0]->{unit_of_work} }
sub status             { $_[0]->{status} }

sub change_status {
    my $self = shift;
    my $status_name = shift;

    if ( $STATUS{$status_name}
        and grep { $_ eq $status_name } @{$STATUS{ $self->status }} )
    {
        $self->{status} = $status_name;
        if( $status_name eq 'persistent' || $status_name eq 'pending' ) {
            unless( $self->unit_of_work ) {
                my $uow = shift ||  confess "need UnitOfWork";
                $self->{unit_of_work} = $uow;
            }
        }
        else {
            #warn $status_name;
        }
    }
    else {
        confess "Can't change status : " . $self->status . " => $status_name";
    }
}

sub is_transient  { $_[0]->status eq 'transient' }
sub is_persistent { $_[0]->status eq 'persistent' }
sub is_detached   { $_[0]->status eq 'detached' }
sub is_pending    { $_[0]->status eq 'pending' }

sub instance { $_[0]->{instance} }

sub reducing {
    my ( $self ) = @_;
    my %result;
    my $class_mapper = $self->instance->__class_mapper__;
    my %primary_key = map { $_ => 1 } @{$class_mapper->table->primary_key};
    for my $prop_name ( $class_mapper->attributes->property_names ) {
        my $prop = $class_mapper->attributes->property($prop_name);
        next unless $prop->type eq 'column';
        my $col_name = $prop->name;
        unless ( $primary_key{$col_name}
            and !defined $self->instance->{$prop_name} )
        {
            $result{$col_name} = $self->instance->{$prop_name};
        }
    }
    return \%result;
}

sub cache_keys {
    my $self = shift;
    my $result = shift || $self->reducing;
    my $class_mapper = $self->instance->__class_mapper__;
    return (
        $class_mapper->primary_cache_key($result),
        $class_mapper->unique_cache_keys($result),
    );
}

sub reflesh {
    my $self = shift;
    my $class_mapper = $self->instance->__class_mapper__;
    my ( $key, @cond )
        = $class_mapper->get_unique_condition( $self->identity_condition );
    my $new_val = $self->unit_of_work->_get_cache($key)
        || $class_mapper->table->_find(@cond);
    if( $new_val ) {
        $self->change_status('persistent');
        $self->unit_of_work->_set_cache($self);
        $self->modify( $new_val );
    }
}

sub modify {
    my $self = shift;
    my $rdata = shift;
    my $class_mapper = $self->instance->__class_mapper__;
    for my $prop_name ( $class_mapper->attributes->property_names ) {
        my $col = $class_mapper->attributes->property($prop_name)->name;
        $self->instance->{$prop_name} = $rdata->{$col} || undef;
    }

    return $self->instance;
}

sub get_val_trigger {
    my ( $self, $name ) = @_;

    my $class_mapper = $self->instance->__class_mapper__;
    if( $self->status eq 'expired' ) {
        $self->reflesh;
    }

    if( $class_mapper->attributes->property($name)->type eq 'relation' ) {
        $self->load_rel_val($name) unless defined $self->instance->{$name};
    }

    $self->demolish if $self->is_transient;
}

sub load_rel_val {
    my $self = shift;
    my $name = shift;
    my $class_mapper = $self->instance->__class_mapper__;
    $class_mapper->attributes->property($name)->get( $name, $self );
}

sub set_val_trigger {
    my ( $self, $name, $val ) = @_;

    if( $self->status eq 'expired' ) {
        $self->reflesh;
    }

    my $class_mapper = $self->instance->__class_mapper__;
    my $prop = $class_mapper->attributes->property($name);
    if ( my $meth = $prop->validation_method ) {
        $self->instance->${meth}($val);
    }
    elsif ( my $code = $prop->validation ) {
        unless ( $code->(@_) ) {
            confess "parameter $name is invalid.";
        }
    }

    if ($self->is_persistent
        and !Data::ObjectMapper::Utils::is_deeply(
            $self->instance->{$name}, $val
        )
    ) {
        $self->{is_modified} = 1;
        $self->{modified_data}->{ $prop->name } = $val;
    }

    $self->demolish if $self->is_transient;
    return;
}

sub is_modified   { $_[0]->{is_modified} }
sub modified_data { $_[0]->{modified_data} }

sub update {
    my ( $self ) = @_;
    confess 'it need to be "persistent" status.' unless $self->is_persistent;
    my $reduce_data = $self->reducing;
    my $modified_data = $self->modified_data;
    my $uniq_cond = $self->identity_condition;
    my $class_mapper = $self->instance->__class_mapper__;
    my $result = $class_mapper->table->update->set(%$modified_data)
        ->where(@$uniq_cond)->execute();
    my $new_val = Data::ObjectMapper::Utils::merge_hashref(
        $reduce_data,
        $modified_data
    );
    $self->modify($new_val);
    $self->{is_modified} = 0;
    $self->{modified_data} = +{};
    $self->change_status('expired');
    return !$result || $self->instance;
}

sub save {
    my ( $self ) = @_;
    confess 'it need to be "pending" status.' unless $self->is_pending;
    my $reduce_data = $self->reducing;
    my $class_mapper = $self->instance->__class_mapper__;

    my $comp_result
        = $class_mapper->table->insert->values(%$reduce_data)->execute();
    $self->modify($comp_result);
    $self->init_identity_condition;
    $self->change_status('expired');
    return $self->instance;
}

sub delete {
    my $self = shift;
    confess 'it need to be "persistent" status.' unless $self->is_persistent;
    my $uniq_cond = $self->identity_condition;
    my $class_mapper = $self->instance->__class_mapper__;
    my $result = $class_mapper->table->delete->where(@$uniq_cond)->execute();
    $self->change_status('detached');
    return $result;
}

sub demolish {
    my $self = shift;
    my $id = refaddr($self->instance) || return;
    delete $INSTANCES{$id} if exists $INSTANCES{$id};
}

sub DESTROY {
    my $self = shift;
    $log->debug("DESTROY $self");
    $self->demolish;
}

1;
