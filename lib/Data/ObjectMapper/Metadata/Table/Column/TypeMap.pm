package Data::ObjectMapper::Metadata::Table::Column::TypeMap;
use strict;
use warnings;
use Data::ObjectMapper::Utils;

our $map = {

    # String
    'varchar'           => 'String',
    'character varying' => 'String',
    'char'              => 'String',
    'character'         => 'String',

    # Int
    'int'       => 'Int',
    'integer'   => 'Int',
    'mediumint' => 'Int',

    # SmallInt
    'tinyint'  => 'SmallInt',
    'smallint' => 'SmallInt',

    # BigInt
    'bigint' => 'BigInt',

    # Boolean
    'boolean' => 'Boolean',
    'bool'    => 'Boolean',

    # Text
    'text' => 'Text',

    # Date
    'date' => 'Date',

    # DateTime
    'datetime'                    => 'DateTime',
    'timestamp'                   => 'DateTime',
    'timestamp without time zone' => 'DateTime',
    'timestamp with time zone'    => 'DateTime',

    # Time
    'time'                   => 'Time',
    'time without time zone' => 'Time',
    'time with time zone'    => 'Time',

    # Interval
    'interval' => 'Interval',

    # Numeric
    'float'            => 'Numeric',
    'decimal'          => 'Numeric',
    'dec'              => 'Numeric',
    'numeric'          => 'Numeric',
    'real'             => 'Numeric',
    'double precision' => 'Numeric',
    'money'            => 'Numeric',
    'double'           => 'Numeric',

    # Blob
    'blob'  => 'Binary',
    'bytea' => 'Binary',

    # Bit
    'bit'         => 'Bit',
    'bit varying' => 'Bit',
};

# Array
our $is_array = qr/^.+\[\]$/;

sub get {
    my $class = shift;
    my $type = shift;

    my $prefix = 'Data::ObjectMapper::Metadata::Table::Column::Type::';

    my $type_class;
    if( $map->{$type} ) {
        $type_class = $prefix . $map->{$type};
    }
    elsif( $type =~ /$type/ ) {
        $type_class = $prefix . 'Array';
    }
    else {
        $type_class = $prefix . 'Undef';
    }

    return Data::ObjectMapper::Utils::load_class($type_class);
}


1;
