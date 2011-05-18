package DBIx::ObjectMapper::Metadata::Table::Column::Type::Blob;
use strict;
use warnings;
use base qw(DBIx::ObjectMapper::Metadata::Table::Column::Type);
use DBIx::ObjectMapper::Engine::DBI::BoundParam;

sub to_storage {
    my ( $self, $val, $column_name ) = @_;
    return $val unless defined $val;
    DBIx::ObjectMapper::Engine::DBI::BoundParam->new(
        value  => $val,
        type   => 'binary',
        column => $column_name,
    );
}

1;
