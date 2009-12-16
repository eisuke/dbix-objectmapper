package Data::ObjectMapper::Engine::DBI::Connector;
use strict;
use warnings;
use base qw(DBIx::Connector);

sub new {
    my $class = shift;
    my $connect_do = $_[3] && ref($_[3]) ? delete $_[3]->{ConnectDo} : undef;

    my $self = $class->SUPER::new(@_);
    $self->{_connect_do} = $connect_do;
    $self;
}

sub _connect {
    my $self = shift;
    my $dbh = $self->SUPER::_connect(@_);
    if( $self->{_connect_do} ) {
        $dbh->do($_) for @{$self->{_connect_do}};
    }
    return $dbh;
}

1;
