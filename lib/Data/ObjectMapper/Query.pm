package Data::ObjectMapper::Query;
use strict;
use warnings;
use Carp::Clan;
use base qw(Data::ObjectMapper::Query::Base);
use Data::ObjectMapper::Query::Select;
use Data::ObjectMapper::Query::Insert;
use Data::ObjectMapper::Query::Update;
use Data::ObjectMapper::Query::Delete;
use Data::ObjectMapper::Query::Count;

sub select { Data::ObjectMapper::Query::Select->new( shift->engine, @_ ) }
sub insert { Data::ObjectMapper::Query::Insert->new( shift->engine, @_ ) }
sub update { Data::ObjectMapper::Query::Update->new( shift->engine, @_ ) }
sub delete { Data::ObjectMapper::Query::Delete->new( shift->engine, @_ ) }
sub count  { Data::ObjectMapper::Query::Count->new( shift->engine, @_ ) }

1;
