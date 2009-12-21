package Data::ObjectMapper::LazyLoadValue;
use strict;
use warnings;
use base qw(Tie::Scalar);

sub TIESCALAR {
    my $class = shift;
    my %attr = @_;

    bless {}, $class;
}

sub FETCH {
    my $self = shift;

}

sub STORE {
    my $self = shift;
    my $val  = shift;

}

sub DESTROY {
    my $self = shift;
}

1;
