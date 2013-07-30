package DBIx::ObjectMapper::Metadata::Table::Column::TypeMap;
use strict;
use warnings;
use DBIx::ObjectMapper::Utils;

sub get {
    my $class    = shift;
    my $type     = shift;
    my $driver   = shift;
    my $prefix   = 'DBIx::ObjectMapper::Metadata::Table::Column::Type::';
    my $is_array = qr/^.+\[\]$/;

    my $type_class;
    if( $driver->type_map($type) ) {
        $type_class = $prefix . $driver->type_map($type);
    }
    elsif( $type =~ /$is_array/ ) {
        $type_class = $prefix . 'Array';
    }
    else {
        $type_class = $prefix . 'Undef';
    }

    return DBIx::ObjectMapper::Utils::load_class($type_class);
}


1;
