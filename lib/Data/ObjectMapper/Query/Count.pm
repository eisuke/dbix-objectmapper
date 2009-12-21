package Data::ObjectMapper::Query::Count;
use strict;
use warnings;
use base qw(Data::ObjectMapper::Query::Select);

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->builder( $self->engine->query->select->column({ count => '*' }) );
    return $self;
}

sub execute {
    my $self = shift;
    return $self->engine->select( $self->builder, sub { $_[0]->[0] } )->first;
}

1;
