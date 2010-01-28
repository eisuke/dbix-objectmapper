package Data::ObjectMapper::Metadata::Table::Column::Type::Int;
use strict;
use warnings;
use base qw(Data::ObjectMapper::Metadata::Table::Column::Type);

sub _init {
    my $self = shift;
    $self->{size} = shift;
}

1;
