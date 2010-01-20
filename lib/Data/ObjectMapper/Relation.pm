package Data::ObjectMapper::Relation;
use strict;
use warnings;
use Carp::Clan qw/^Data::ObjectMapper/;
use Data::ObjectMapper::Session::Array;

my %CASCADE_TYPES = (
    # type         => [ single, multi ]
    save_update    => [ 0, 0 ],
    delete         => [ 0, 0 ],
    detach         => [ 0, 0 ],
    reflesh_expire => [ 0, 0 ],
);

sub new {
    my ( $class, $rel_class, $option ) = @_;

    my $is_multi = $class->initial_is_multi || 0;

    my $self = bless +{
        name      => undef,
        rel_class => $rel_class,
        option    => $option,
        type      => 'rel',
        cascade   => +{},
        is_multi  => $is_multi,
    }, $class;

    $self->_init_option;
    return $self;
}

sub is_multi { $_[0]->{is_multi} }

sub _init_option {
    my $self = shift;

    if( my $cascade_option = $self->{option}{cascade} ) {
        $cascade_option =~ s/\s//g;
        my %cascade = map { $_ => 1 } split ',', $cascade_option;
        if( $cascade{all} ) {
            $self->{cascade}{$_} = 1 for keys %CASCADE_TYPES;
        }
        else {
            for my $c ( keys %CASCADE_TYPES ) {
                $self->{cascade}{$c} = 1 if $cascade{$c};
            }
        }
    }


}

{
    no strict 'refs';
    my $pkg = __PACKAGE__;
    for my $cascade ( keys %CASCADE_TYPES ) {
        *{"$pkg\::is_cascade_$cascade"} = sub {
            my $self = shift;
            return $self->{cascade}{$cascade} || do {
                if( $self->is_multi ) {
                    $CASCADE_TYPES{$cascade}->[1];
                }
                else {
                    $CASCADE_TYPES{$cascade}->[0];
                }
            }
        };
    }
};

sub type      { $_[0]->{type} }
sub rel_class { $_[0]->{rel_class} }
sub option    { $_[0]->{option} }
sub mapper    { $_[0]->rel_class->__class_mapper__ }
sub table     { $_[0]->mapper->table }

sub name {
    my $self = shift;
    $self->{name} = shift if @_;
    return $self->{name};
}

sub foreign_key {}

sub validation {}

sub get_one {
    my $self = shift;
    my $name = shift;
    my $mapper = shift;
    my $cond = $mapper->relation_condition->{$name} || return;

    $mapper->instance->{$name} = $mapper->unit_of_work->get(
        $self->rel_class => $cond
    );
}

sub get_multi {
    my $self = shift;
    my $name = shift;
    my $mapper = shift;
    my $cond = $mapper->relation_condition->{$name} || return;

    my $rel_mapper = $self->mapper;
    my @new_val
        = $mapper->unit_of_work->query( $self->rel_class )->where(@$cond)
        ->order_by( map { $rel_mapper->table->c($_) }
            @{ $rel_mapper->table->primary_key } )->execute->all;

    $mapper->instance->{$name} = Data::ObjectMapper::Session::Array->new(
        $mapper,
        @new_val
    );
}


sub relation_condition {}

sub identity_condition {
    my $self = shift;
    my $mapper = shift;
    return $self->is_multi
        ? $self->get_multi_cond($mapper)
        : $self->get_one_cond($mapper);
}

sub get_one_cond {
    my $self = shift;
    my $mapper = shift;
    my $class_mapper = $mapper->instance->__class_mapper__;
    my $rel_mapper = $self->mapper;

    my $fk = $self->foreign_key($class_mapper->table, $rel_mapper->table);

    my @cond;
    for my $i ( 0 .. $#{$fk->{keys}} ) {
        my $val = $mapper->instance->{$fk->{keys}->[$i]};
        next unless defined $val;
        push @cond, $rel_mapper->table->c( $fk->{refs}->[$i] ) == $val;
    }

    return @cond;
}

sub get_multi_cond {
    my $self = shift;
    my $mapper = shift;
    my $class_mapper = $mapper->instance->__class_mapper__;
    my $rel_mapper = $self->mapper;
    my $fk = $self->foreign_key($class_mapper->table, $rel_mapper->table);

    my @cond;
    for my $i ( 0 .. $#{$fk->{keys}} ) {
        my $val = $mapper->instance->{$fk->{refs}->[$i]};
        push @cond, $rel_mapper->table->c( $fk->{keys}->[$i] ) == $val;
    }

    return @cond;
}

sub mapping {
    my $self = shift;
    my $data = shift;
    return $self->mapper->mapping($data);
}

sub is_self_reference {
    my $self = shift;
    my $refs_table = shift;
    return $refs_table eq $self->table;
}

sub cascade_delete {
    my $self = shift;
    my $mapper = shift;

    return unless $self->is_cascade_delete;

    my @cond = $self->identity_condition($mapper);
    return if !@cond || ( @cond == 1 and !defined $cond[0]->[2] );
    $self->table->delete->where(@cond)->execute;
}

sub cascade_update {
    my $self = shift;
    my $name = shift;
    my $mapper = shift;

    return unless $self->is_cascade_save_update and $mapper->is_modified;

    my $uniq_cond = $mapper->relation_condition->{$name};
    my $modified_data = $mapper->modified_data;
    my $class_mapper = $mapper->instance->__class_mapper__;
    my $rel_mapper = $self->mapper;

    my %sets;
    my $fk = $self->foreign_key($class_mapper->table, $rel_mapper->table);
    for my $i ( 0 .. $#{$fk->{keys}} ) {
        if( my $m = $modified_data->{$fk->{refs}->[$i]} ) {
            $sets{$fk->{keys}->[$i]} = $m;
        }
    }
    return unless keys %sets;

    $self->table->update->set(%sets)->where(@$uniq_cond)->execute;
}

sub cascade_save {
    my $self = shift;
    my $name = shift;
    my $mapper = shift;
    my $instance = shift;

    my $class_mapper = $mapper->instance->__class_mapper__;
    my $rel_mapper = $self->mapper;

    my %sets;
    my $fk = $self->foreign_key($class_mapper->table, $rel_mapper->table);
    for my $i ( 0 .. $#{$fk->{keys}} ) {
        $instance->{ $fk->{keys}->[$i] }
            = $mapper->instance->{ $fk->{refs}->[$i] };
    }

    $mapper->unit_of_work->add($instance);
    $instance->__mapper__->save;
}

1;
