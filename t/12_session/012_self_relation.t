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
        q{CREATE TABLE bbs( id integer primary key, comment text, parent_id integer REFERENCES bbs(id), created timestamp)},
    ],
});

my $mapper = DBIx::ObjectMapper->new( engine => $engine );

my $bbs = $mapper->metadata->table( 'bbs' => 'autoload' );

$bbs->insert->values($_)->execute for(
    { comment => 'first' },
    { comment => 'second' },
    { comment => 'child', parent_id => 1 },
    { comment => 'child2', parent_id => 1 },
    { comment => 'grandchild', parent_id => 3 },
);

ok $mapper->maps(
    $bbs => 'MyTest12::BBS',
    constructor => { auto => 1 },
    accessors   => { auto => 1 },
    attributes  => {
        properties => {
            parent => {
                isa => $mapper->relation( 'belongs_to' => 'MyTest12::BBS' ),
            },
            children => {
                isa => $mapper->relation( 'has_many' => 'MyTest12::BBS' ),
            }
        }
    }
);

sub check {
    my $first = shift;
    is $first->id, 1;

    is $first->parent, undef;
    ok $first->children;
    is ref($first->children), 'ARRAY';

    my $c = $first->children->[0];
    is $c->id, 3;
    is $c->comment, 'child';
    is $c->parent_id, 1;
    is $c->parent->id, 1;
    is $c->parent->children->[0]->id, $c->id;
    is $c->parent->children->[0]->parent->id, 1;

    ok $first->children->[1];
    is $first->children->[1]->comment, 'child2';

    my $grandchild = $first->children->[0]->children->[0];
    is $first->children->[0]->children->[0]->comment, 'grandchild';

    is $grandchild->parent->children->[0]->parent->children->[0]->parent->children->[0]->parent->parent->children->[0]->parent->id, 1;

    eval "require Test::Memory::Cycle";
    unless( $@ ) {
        Test::Memory::Cycle::memory_cycle_ok( $first );
    }
}

subtest 'basic' => sub {
    my $session = $mapper->begin_session;
    check($session->get( 'MyTest12::BBS' => 1 ));
    is $session->uow->query_cnt, 8;
    done_testing;
};

subtest 'query' => sub {
    my $session = $mapper->begin_session;
    my $attr = $mapper->attribute('MyTest12::BBS');
    my $it = $session->search('MyTest12::BBS')->order_by($attr->p('id'))->execute;
    check($it->[0]);
    is $session->uow->query_cnt, 8;
    done_testing;
};

subtest 'eagerload' => sub {
    my $session = $mapper->begin_session;
    my $first = $session->get( 'MyTest12::BBS' => 1, { eagerload => 'children' } );

    check($first);
    is $session->uow->query_cnt, 7;
    done_testing;
};

subtest 'eagerload2' => sub {
    my $session = $mapper->begin_session;
    my $first = $session->get( 'MyTest12::BBS' => 1, { eagerload => [ 'parent', 'children'] } );
    check($first);
    is $session->uow->query_cnt, 7;
    done_testing;
};

subtest 'join nested' => sub {
    my $session = $mapper->begin_session;
    my $attr = $mapper->attribute('MyTest12::BBS');
    my $first = $session->search('MyTest12::BBS')->filter( $attr->p('children.parent.id') == 1 )->first;
    check($first);
    is $session->uow->query_cnt, 8;
    done_testing;
};

done_testing();
