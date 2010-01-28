package Data::ObjectMapper::Metadata::Table::Column::Type::Interval;
use strict;
use warnings;
use base qw(Data::ObjectMapper::Metadata::Table::Column::Type::DateTime);

sub default_type { 'interval' }

1;
