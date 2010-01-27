package Data::ObjectMapper::Metadata::Table::Column::Type::String;
use strict;
use warnings;
use base qw(Data::ObjectMapper::Metadata::Table::Column::Type);
use Encode;

sub from_storage {
    my ( $self, $val ) = @_;

    if( $val and $self->utf8 and !Encode::is_utf8($val) ) {
        $val = Encode::decode( 'utf8', $val )
    }

    return $val;
}

sub to_storage {
    my ( $self, $val ) = @_;

    if( defined $val and $self->utf8 and Encode::is_utf8($val) ) {
        $val = Encode::encode( 'utf8', $val )
    }

    return $val;
}

1;
