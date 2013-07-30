package DBIx::ObjectMapper::Engine::DBI::BoundParam;
use strict;
use warnings;
use Carp::Clan qw/^DBIx::ObjectMapper/;
use Params::Validate qw(:all);

my $ATTRIBUTES = {
    value  => { type => SCALAR },
    type   => { type => SCALAR },
    column => { type => SCALAR },
};

sub new {
    my $class = shift;
    my %attr = validate( @_, $ATTRIBUTES );
    return bless \%attr, $class;
}

sub value  { $_[0]->{value}  }
sub type   { $_[0]->{type}   }
sub column { $_[0]->{column} }

1;
