use strict;
use warnings;
use Test::More;

use Data::ObjectMapper;
use Data::ObjectMapper::Engine::DBI;

my $engine = Data::ObjectMapper::Engine::DBI->new({
    dsn => 'DBI:SQLite:',
    username => '',
    password => '',
    on_connect_do => [
        q{CREATE TABLE player (id integer primary key, name text, play text)},
    ],
});

my $mapper = Data::ObjectMapper->new( engine => $engine );
$mapper->metadata->autoload_all_tables;
my $player = $mapper->metadata->t('player');

ok $mapper->maps(
    $player => 'MyTest17::Player',
    accessors => { auto => 1 },
    constructor => { auto => 1 },
);

eval {
    my $session = $mapper->begin_session( autocommit => 0 );
    $session->add_all(
        MyTest17::Player->new( name => 'first' ),
        MyTest17::Player->new( name => 'second' ),
        MyTest17::Player->new( name => 'third' ),
    );
    die;
};

{
    my $session = $mapper->begin_session;
    is $session->query('MyTest17::Player')->count, 0;
};

done_testing;
