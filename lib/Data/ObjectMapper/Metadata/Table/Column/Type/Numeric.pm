package Data::ObjectMapper::Metadata::Table::Column::Type::Numeric;
use strict;
use warnings;
use Carp::Clan;
use base qw(Data::ObjectMapper::Metadata::Table::Column::Type);
use Scalar::Util qw(looks_like_number);

sub _init {
    my $self = shift;
    if( @_ ) {
        my ( $precision, $scale ) = @_;
        $self->{precision} = $precision || confess "precision not found.";
        $self->{scale}     = $scale     || 0;
    }
}

sub size {
    my $self = shift;

    if( @_ ) {
        my $size = shift;
        if( $size =~ /,/ ) {
            # pg's "size" is "$precision,$scale", but mysql is "$precision" ....
            my ( $precision, $scale ) = split ',', $size;
            $self->_init($precision, $scale);
            $self->{size} = "$precision,$scale";
        }
        else {
            $self->_init($size);
            $self->{size} = $size;
        }
    }

    return $self->{size};
}

1;
