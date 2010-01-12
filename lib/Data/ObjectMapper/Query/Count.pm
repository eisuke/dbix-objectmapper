package Data::ObjectMapper::Query::Count;
use strict;
use warnings;
use base qw(Data::ObjectMapper::Query::Select);

sub execute {
    my $self = shift;
    return $self->count;
}

1;
