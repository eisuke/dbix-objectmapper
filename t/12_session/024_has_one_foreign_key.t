use strict;
use warnings;
use Test::More;

use DBIx::ObjectMapper;
use DBIx::ObjectMapper::Engine::DBI;

my $mapper = DBIx::ObjectMapper->new(
    engine => DBIx::ObjectMapper::Engine::DBI->new({
        dsn => 'DBI:SQLite:',
        username => '',
        password => '',
        on_connect_do => [
            q{CREATE TABLE tab1 (id integer primary key)},
            q{CREATE TABLE tab2 (id integer primary key, tab1_id integer REFERENCES tab1(id) UNIQUE)},
            q{CREATE TABLE tab3 (id integer primary key)},
            q{CREATE TABLE tab4 (id integer primary key, parent_id integer REFERENCES tab3(id))},
        ]
    }),
);

$mapper->metadata->autoload_all_tables;
my $tab1 = $mapper->metadata->t('tab1');
my $tab2 = $mapper->metadata->t('tab2');
$tab1->insert->values(id => 1)->execute();
$tab2->insert->values(id => 2, tab1_id => 1 )->execute();
$tab2->insert->values(id => 1, tab1_id => 2 )->execute();

is_deeply $tab2->foreign_key, [
    {
        table => 'tab1',
        refs => ['id'],
        keys => ['tab1_id'],
    }
];

ok $mapper->maps(
    $tab1 => 'MyTest::Tab1',
    accessors => { auto => 1 },
    constructor => { auto => 1 },
    attributes => {
        properties => {
            tab2 => {
                isa => $mapper->relation( has_one => 'MyTest::Tab2' )
            }
        }
    }
);

ok $mapper->maps(
    $tab2 => 'MyTest::Tab2',
    accessors => { auto => 1 },
    constructor => { auto => 1 },
);

{
    my $session = $mapper->begin_session;
    my $t1 = $session->get( 'MyTest::Tab1' => 1 );
    is $t1->id, 1;
    ok $t1->tab2;
    is $t1->tab2->id, 2;
    is $t1->tab2->tab1_id, 1;
};

my $tab3 = $mapper->metadata->t('tab3');
my $tab4 = $mapper->metadata->t('tab4');
$tab3->insert->values(id => 1)->execute();
$tab3->insert->values(id => 2)->execute();
$tab4->insert->values(id => 2, parent_id => 1 )->execute();

ok $mapper->maps(
    $tab3 => 'MyTest::Tab3',
    accessors => { auto => 1 },
    constructor => { auto => 1 },
    attributes => {
        properties => {
            tab4 => {
                isa => $mapper->relation( has_one => 'MyTest::Tab4' )
            }
        }
    }
);

ok $mapper->maps(
    $tab4 => 'MyTest::Tab4',
    accessors => { auto => 1 },
    constructor => { auto => 1 },
    attributes => {
        properties => {
            parent => {
                isa => $mapper->relation( belongs_to => 'MyTest::Tab3' ),
            }
        }
    }
);

{
    my $session = $mapper->begin_session;
    my $t3 = $session->get( 'MyTest::Tab3' => 2 );
    is $t3->id, 2;
    ok $t3->tab4;
    is $t3->tab4->id, 2;
    ok $t3->tab4->parent;
    is $t3->tab4->parent->id, 1;
};

done_testing;

