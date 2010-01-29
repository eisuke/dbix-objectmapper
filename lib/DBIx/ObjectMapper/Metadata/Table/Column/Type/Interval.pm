package DBIx::ObjectMapper::Metadata::Table::Column::Type::Interval;
use strict;
use warnings;
use base qw(DBIx::ObjectMapper::Metadata::Table::Column::Type::DateTime);

sub default_type { 'interval' }

1;
