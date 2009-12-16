package Data::ObjectMapper::Iterator;
use strict;
use warnings;
use Carp::Clan;

sub new {
    my ( $class, $data_ref ) = @_;
    confess __PACKAGE__ . "->new([ARRAYREF])" unless ref $data_ref eq 'ARRAY';
    my $self = $class->SUPER::new();
    return $self;
}

sub next {}

sub reset {
    my $self = shift;
    $self->{cursor} = 0;
    return $self;
}

sub all {

}

1;
