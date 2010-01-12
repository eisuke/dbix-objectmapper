package Data::ObjectMapper::Relation::HasOne;
use strict;
use warnings;
use base qw(Data::ObjectMapper::Relation);

sub get {
    my $self = shift;
    $self->get_one(@_);
}

1;
