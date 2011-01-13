use strict;
use warnings;
use Test::More;
use DBIx::ObjectMapper::Engine::DBI;

use DBIx::ObjectMapper;
use DBIx::ObjectMapper::Engine::DBI;
use DBIx::ObjectMapper::Metadata::Polymorphic;

my $mapper = DBIx::ObjectMapper->new(
    engine => DBIx::ObjectMapper::Engine::DBI->new({
        dsn => 'DBI:SQLite:',
        username => '',
        password => '',
        on_connect_do => [
            q{CREATE TABLE parent (id integer primary key)},
            q{CREATE TABLE child (id integer primary key, parent_id integer REFERENCES parent(id))},
        ]
    }),
);
$mapper->metadata->autoload_all_tables;

ok my $table = DBIx::ObjectMapper::Metadata::Polymorphic->new(
    $mapper->metadata->t('parent'),
    $mapper->metadata->t('child'),
);

ok $table->column('id');
ok $table->column('parent_id');


done_testing;

