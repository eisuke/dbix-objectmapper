package DBIx::ObjectMapper::Query;
use strict;
use warnings;
use Carp::Clan qw/^DBIx::ObjectMapper/;
use base qw(DBIx::ObjectMapper::Query::Base);
use DBIx::ObjectMapper::Query::Select;
use DBIx::ObjectMapper::Query::Insert;
use DBIx::ObjectMapper::Query::Update;
use DBIx::ObjectMapper::Query::Delete;
use DBIx::ObjectMapper::Query::Count;

sub select { DBIx::ObjectMapper::Query::Select->new( shift->metadata, @_ ) }
sub insert { DBIx::ObjectMapper::Query::Insert->new( shift->metadata, @_ ) }
sub update { DBIx::ObjectMapper::Query::Update->new( shift->metadata, @_ ) }
sub delete { DBIx::ObjectMapper::Query::Delete->new( shift->metadata, @_ ) }
sub count  { DBIx::ObjectMapper::Query::Count->new( shift->metadata, @_ ) }

1;
