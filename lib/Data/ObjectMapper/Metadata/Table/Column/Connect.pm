package Data::ObjectMapper::Metadata::Table::Column::Connect;
use strict;
use warnings;
use overload
    '""' => sub {  $_[0]->{col1} . ' || ' . $_[0]->{col2} },
    fallback => 1,
;

sub new {
    my ( $class, $col1, $col2 ) = @_;
    bless { col1 => $col1, col2 => $col2 }, $class;
}

1;
