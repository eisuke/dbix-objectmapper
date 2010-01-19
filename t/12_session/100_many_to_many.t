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
        q{CREATE TABLE left( id integer primary key)},
        q{CREATE TABLE right( id integer primary key)},
        q{CREATE TABLE association(left_id integer references left(id), right_id integer references right(id), primary key (left_id, right_id))},
    ],
});

my $mapper = Data::ObjectMapper->new( engine => $engine );

$mapper->metadata->autoload_all_tables;
my $left = $mapper->metadata->t('left');
my $right = $mapper->metadata->t('right');
my $association = $mapper->metadata->t('association');

$left->insert->values({ id => 1 })->execute;
for( 1 .. 5 ) {
    $right->insert->values({ id => $_ })->execute;
    $association->insert->values({left_id => 1, right_id => $_ })->execute;
}

ok $mapper->maps(
    $left => 'MyTest14::Parent',
    constructor => { auto => 1 },
    accessors   => { auto => 1 },
    attributes  => {
        properties => {
            children => {
                isa => $mapper->relation(
                    'many_to_many' => $association => 'MyTest14::Child',
                )
            }
        }
    }
);

ok $mapper->maps(
    $right => 'MyTest14::Child',
    constructor => { auto => 1 },
    accessors   => { auto => 1 },
);

{
    my $session = $mapper->begin_session( autocommit => 0 );
    ok my $p = $session->get( 'MyTest14::Parent' => 1 );
    is $p->id, 1;
    ok $p->children;
    is ref($p->children), 'ARRAY';
    is scalar(@{$p->children}), 5;
    for my $c ( @{$p->children} ) {
        ok $c->id;
    }

    push @{$p->children}, MyTest14::Child->new( id => 6 );
    $session->commit;
};

{ # check
    my $session = $mapper->begin_session();
    ok my $p = $session->get( 'MyTest14::Parent' => 1 );
    is scalar(@{$p->children}), 6;
};

done_testing;
