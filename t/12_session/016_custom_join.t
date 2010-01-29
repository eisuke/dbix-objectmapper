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
        q{CREATE TABLE parent (id integer primary key)},
        q{CREATE TABLE child (id integer primary key, parent_id integer REFERENCES parent(id))},
    ],
});

my $mapper = DBIx::ObjectMapper->new( engine => $engine );

$mapper->metadata->autoload_all_tables;
$mapper->metadata->t('parent')->insert->values(id => 1)->execute();
$mapper->metadata->t('child')->insert->values({parent_id => 1})->execute() for 0 .. 4;

$mapper->maps(
    $mapper->metadata->t('parent') => 'MyTest16::Parent',
    constructor => +{ auto => 1 },
    accessors   => +{ auto => 1 },
);

$mapper->maps(
    $mapper->metadata->t('child') => 'MyTest16::Child',
    constructor => +{ auto => 1 },
    accessors   => +{ auto => 1 },
);

{
    my $session = $mapper->begin_session;
    my $parent = $mapper->metadata->t('parent');
    my $child  = $mapper->metadata->t('child');
    my $it = $session->query('MyTest16::Parent')
        ->join([ $child, [
            $parent->c('id') == $child->c('parent_id'),
            $child->c('id') > 0
        ] ])
        ->where( $child->c('id') == 1 )->execute;
    my $loop_cnt = 0;
    while( my $p = $it->next ) {
        is $p->id, 1;
        $loop_cnt++;
    }
    is $loop_cnt, 1;
    is $session->uow->query_cnt, 1;
};

done_testing;
