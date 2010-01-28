use strict;
use warnings;
use Test::More;
use Data::ObjectMapper::Engine::DBI;
use Data::ObjectMapper;


plan skip_all => 'TODO';



my ($dsn, $user, $pass) = @ENV{map { "MAPPER_TEST_PG_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{MAPPER_TEST_PG_DSN}, _USER and _PASS to run this test' unless ($dsn && $user);


my $engine = Data::ObjectMapper::Engine::DBI->new({
    dsn => $dsn,
    username => $user,
    password => $pass,
    on_connect_do => [
        q{CREATE TEMP TABLE artist (id serial primary key, name text)},
    ],
});

# array
# bit
# timestamp
# binary

done_testing;
