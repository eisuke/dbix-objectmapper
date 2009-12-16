package Data::ObjectMapper::Query;
use strict;
use warnings;
use Carp::Clan;

use Data::ObjectMapper::Query::Select;
use Data::ObjectMapper::Query::Insert;
use Data::ObjectMapper::Query::Update;
use Data::ObjectMapper::Query::Delete;
use Data::ObjectMapper::Query::Count;

sub new {
    my $class = shift;
    my $engine = shift || confess 'usage: ' . $class . '->new($engine)';
    my $callback = shift || undef;
    bless { engine => $engine, callback => $callback }, $class;
}

sub engine   { $_[0]->{engine} }
sub callback { $_[0]->{callback} }

sub builder {
    my $self = shift;
    $self->{builder} = shift if @_;
    return $self->{builder};
}

sub execute { die "Abstract Method" }

sub select { Data::ObjectMapper::Query::Select->new(shift->engine, @_) }
sub insert { Data::ObjectMapper::Query::Insert->new(shift->engine, @_) }
sub update { Data::ObjectMapper::Query::Update->new(shift->engine, @_) }
sub delete { Data::ObjectMapper::Query::Delete->new(shift->engine, @_) }
sub count  { Data::ObjectMapper::Query::Count->new(shift->engine, @_) }

1;
