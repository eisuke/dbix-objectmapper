package Data::ObjectMapper::Metadata::Table::Column::Type::Numeric;
use strict;
use warnings;
use Carp::Clan;
use base qw(Data::ObjectMapper::Metadata::Table::Column::Type);
use Scalar::Util qw(looks_like_number);

sub _init {
    my $self = shift;
    $self->size(@_) if @_;
}

sub size {
    my $self = shift;

    if( @_ ) {
        if( @_ == 1 and $_[0] =~ /,/ ) {
            # pg's "size" is "$precision,$scale", but mysql is "$precision" ....
            my ( $precision, $scale ) = split ',', $_[0];
            $self->{precision} = $precision;
            $self->{scale}     = $scale     || 0;
            $self->{size} = "$precision,$scale";
        }
        elsif( @_ == 2 ) {
            my ( $precision, $scale ) = @_;
            $self->{precision} = $precision;
            $self->{scale}     = $scale;
            $self->{size} = "$precision,$scale";
        }
        else {
            $self->{size} = $_[0];
        }
    }

    return $self->{size};
}

1;
