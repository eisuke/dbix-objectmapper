package Data::ObjectMapper::Relation;
use strict;
use warnings;
use Carp::Clan;

sub new {
    my ( $class, $rel_class, $option ) = @_;

    bless +{
        name  => undef,
        rel_class => $rel_class,
        option   => $option,
        type => 'rel',
    }, $class;
}

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

sub validation {}

sub get_one {
    my $self = shift;
    my $name = shift;
    my $mapper = shift;
    my $class_mapper = $mapper->instance->__class_mapper__;
    my $rel_mapper = $self->mapper;
    my $fk = $class_mapper->table->get_foreign_key_by_table(
        $rel_mapper->table,
    );

    my @cond;
    for my $i ( 0 .. $#{$fk->{keys}} ) {
        push @cond,
            $rel_mapper->table->c( $fk->{refs}->[$i] )
                == $mapper->instance->{$fk->{keys}->[$i]};
    }

    $mapper->instance->{$name} = $mapper->unit_of_work->get(
        $self->rel_class => \@cond
    );
}

sub get_multi {
    my $self = shift;
    my $name = shift;
    my $mapper = shift;
    my $class_mapper = $mapper->instance->__class_mapper__;
    my $rel_mapper = $self->mapper;
    my $fk = $rel_mapper->table->get_foreign_key_by_table(
        $class_mapper->table
    );

    my @cond;
    for my $i ( 0 .. $#{$fk->{keys}} ) {
        push @cond,
            $rel_mapper->table->c( $fk->{keys}->[$i] )
                == $mapper->instance->{$fk->{refs}->[$i]};
    }

    my @new_val
        = $mapper->unit_of_work->query( $self->rel_class )->where(@cond)
        ->order_by( map { $rel_mapper->table->c($_) }
            @{ $rel_mapper->table->primary_key } )->execute->all;

    $mapper->instance->{$name} = \@new_val;
}

sub is_multi { 0 }

1;
