package Data::ObjectMapper::Mapper::Instance;
use strict;
use warnings;
use Carp::Clan;
use Scalar::Util qw(refaddr);
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
    my ( $class, $mapper, $instance ) = @_;
    return $class->get($instance) || $class->create($mapper, $instance);
}

sub create {
    my ( $class, $mapper, $instance ) = @_;
    my $self = bless {
        mapper             => $mapper,
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

sub init_identity_condition {
    my $self = shift;
    my $record = shift || $self->reducing;
    my $identity_condition
        = +[ map { $self->mapper->table->c($_) == $record->{$_} }
            @{ $self->mapper->table->primary_key } ];

    if( @$identity_condition ) {
        return $self->{identity_condition} = $identity_condition;
    }
    elsif( my $unique_key = @{ $self->mapper->table->unique_key } ) {
        for my $uniq ( @$unique_key ) {
            return $self->{identity_condition} = map {
                $self->mapper->table->c($_) == $record->{$_} } @{$uniq->[1]};
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

sub mapper   { $_[0]->{mapper} }
sub instance { $_[0]->{instance} }

sub reducing {
    my ( $self ) = @_;
    my %result;
    for my $attr ( $self->mapper->get_attributes_name ) {
        my $col_name = $self->mapper->get_attribute($attr)->{isa}->name;
        $result{$col_name} = $self->instance->{$attr};
    }
    return \%result;
}

sub cache_keys {
    my $self = shift;
    my $result = shift || $self->reducing;
    return (
        $self->mapper->primary_cache_key($result),
        $self->mapper->unique_cache_keys($result),
    );
}

sub reflesh {
    my $self = shift;
    my $new_val = $self->mapper->table->_find(@{$self->identity_condition});
    if( $new_val ) {
        $self->change_status('persistent');
        $self->unit_of_work->_set_cache($self);
        $self->modify( $new_val );
    }
}

sub modify {
    my $self = shift;
    my $rdata = shift;
    my $mapper = $self->mapper;
    for my $attr ( $mapper->get_attributes_name ) {
        my $col    = $mapper->get_attribute($attr)->{isa}->name;
        $self->instance->{$attr} = $rdata->{$col} || undef;
    }

    return $self->instance;
}

sub get_val_trigger {
    my ( $self, $name ) = @_;
    if( $self->status eq 'expired' ) {
        $self->reflesh;
    }
}

sub set_val_trigger {
    my ( $self, $name, $val ) = @_;

    if( $self->status eq 'expired' ) {
        $self->reflesh;
    }

    my $attr_config = $self->mapper->get_attribute($name);
    if ( my $meth = $attr_config->{validation_method} ) {
        $self->instance->${meth}($val);
    }
    elsif ( $attr_config->{validation}
        and my $code = $attr_config->{isa}->validation )
    {
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
        $self->{modified_data}->{ $attr_config->{isa}->name } = $val;
    }

    return;
}

sub is_modified   { $_[0]->{is_modified} }
sub modified_data { $_[0]->{modified_data} }

sub update {
    my ( $self ) = @_;
    confess "XXXX" unless $self->is_persistent;
    my $reduce_data = $self->reducing;
    my $modified_data = $self->modified_data;
    my $uniq_cond = $self->identity_condition;

    my $result = $self->mapper->table->update->set(%$modified_data)
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
    confess "XXXX" unless $self->is_pending;
    my $reduce_data = $self->reducing;
    my $comp_result
        = $self->mapper->table->insert->values(%$reduce_data)->execute();
    $self->modify($comp_result);
    $self->init_identity_condition;
    $self->change_status('expired');
    return $self->instance;
}

sub delete {
    my $self = shift;
    confess "XXXX" unless $self->is_persistent;
    my $uniq_cond = $self->identity_condition;
    my $result = $self->mapper->table->delete->where(@$uniq_cond)->execute();
    $self->change_status('detached');
    return $result;
}

sub demolish {
    my $self = shift;
    my $id = refaddr($self->instance);
    delete $INSTANCES{$id} if exists $INSTANCES{$id};
}

sub DESTROY {
    my $self = shift;
    warn "$self DESTROY" if $ENV{DOM_CHECK_DESTROY};
    $self->demolish;
}

1;
