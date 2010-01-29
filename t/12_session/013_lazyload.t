use strict;
use warnings;
use Test::More;

use DBIx::ObjectMapper;
use DBIx::ObjectMapper::Engine::DBI;

my $engine = DBIx::ObjectMapper::Engine::DBI->new({
    dsn => 'DBI:SQLite:',
    username => '',
    password => '',
    on_connect_do => [
        q{CREATE TABLE lazyload( id integer primary key, comment text, add_comment1 text, add_comment2 text, add_comment3 text)},
    ],
});

my $mapper = DBIx::ObjectMapper->new( engine => $engine );

my $lazy = $mapper->metadata->table( 'lazyload' => 'autoload' );

$lazy->insert->values($_)->execute for(
    { comment => 'first', add_comment1 => 'first add_comment1', add_comment2 => 'first add_comment2', add_comment3 => 'first add_comment3' },
    { comment => 'second' },
);

ok $mapper->maps(
    $lazy => 'MyTest13::Lazy',
    constructor => { auto => 1 },
    accessors   => { auto => 1 },
    attributes  => {
        properties => {
            comment => {
                lazy => 1,
            },
            add_comment1 => {
                lazy => 'add_comment',
            },
            add_comment2 => {
                lazy => 'add_comment',
            },
            add_comment3 => {
                lazy => 'add_comment',
            },
        }
    }
);


{
    my $session = $mapper->begin_session;
    my $d = $session->get( 'MyTest13::Lazy' => 1 );
    is $d->id, 1;
    is $d->comment, 'first'; # execute query
    is $d->add_comment1, 'first add_comment1';
    is $d->add_comment2, 'first add_comment2';
    is $d->add_comment3, 'first add_comment3';
    is $session->uow->query_cnt, 3;
};

done_testing;
