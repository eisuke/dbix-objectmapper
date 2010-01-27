package Data::ObjectMapper::Metadata::Table::Column::Type;
use strict;
use warnings;
use Scalar::Util qw(looks_like_number);

sub new {
    my $class = shift;
    my $pkg = __PACKAGE__;
    my ( $type ) = ( $class =~ /^$pkg\::(\w+)$/ );

    my $self = bless {
        type     => $type ? lc($type) : undef,
        realtype => undef,
        size     => undef,
        utf8     => undef,
    }, $class;

    my $size = undef;
    unless( @_ % 2 == 0 ) {
        $size = shift;
    }

    my %args = @_;
    $self->{size} = $size if $size and looks_like_number( $size );
    $self->{utf8} = 1 if $args{utf8};
    $self->{realtype} = $args{realtype} if exists $args{realtype};

    $self->_init(@_);
    return $self;
}

sub type     { $_[0]->{type} }
sub size     { $_[0]->{size} }
sub utf8     { $_[0]->{utf8} }
sub realtype { $_[0]->{realtype} }

sub _init {}

sub from_storage {
    my ( $self, $val ) = @_;
    return $val;
}

sub to_storage {
    my ( $self, $val ) = @_;
    return $val;
}

1;
