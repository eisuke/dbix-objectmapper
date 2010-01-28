package Data::ObjectMapper::Metadata::Table::Column::Type::Time;
use strict;
use warnings;
use base qw(Data::ObjectMapper::Metadata::Table::Column::Type::DateTime);

sub default_type { 'time' }

1;
