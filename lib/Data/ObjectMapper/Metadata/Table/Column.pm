package Data::ObjectMapper::Metadata::Table::Column;
use strict;
use warnings;
use base qw(Data::ObjectMapper::Metadata::Table::Column::Base);
use Data::ObjectMapper::Metadata::Table::Column::Func;

sub func {
    my $self = shift;
    return Data::ObjectMapper::Metadata::Table::Column::Func->new(
        $self,
        @_,
    );
}

1;
