package Data::ObjectMapper::Metadata::Table::Column::Type::Array;
use strict;
use warnings;
use base qw(Data::ObjectMapper::Metadata::Table::Column::Type);

sub _init {
    my $self = shift;
    $self->{array_type} = shift || undef;
}

1;
