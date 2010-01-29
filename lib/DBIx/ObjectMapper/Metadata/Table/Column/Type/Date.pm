package DBIx::ObjectMapper::Metadata::Table::Column::Type::Date;
use strict;
use warnings;
use base qw(DBIx::ObjectMapper::Metadata::Table::Column::Type::DateTime);

sub default_type { 'date' }

1;
