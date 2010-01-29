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
        q{CREATE TABLE left( id integer primary key)},
        q{CREATE TABLE right( id integer primary key)},
        q{CREATE TABLE association(left_id integer references left(id), right_id integer references right(id), primary key (left_id, right_id))},
    ],
});

my $mapper = DBIx::ObjectMapper->new( engine => $engine );

$mapper->metadata->autoload_all_tables;
my $left = $mapper->metadata->t('left');
my $right = $mapper->metadata->t('right');
my $association = $mapper->metadata->t('association');

ok $mapper->maps(
    $left => 'MyTest14::Parent',
    constructor => { auto => 1 },
    accessors   => { auto => 1 },
    attributes  => {
        properties => {
            children => {
                isa => $mapper->relation(
                    'many_to_many' => $association => 'MyTest14::Child',
                    { cascade => 'all' }
                )
            }
        }
    }
);

ok $mapper->maps(
    $right => 'MyTest14::Child',
    constructor => { auto => 1 },
    accessors   => { auto => 1 },
    attributes  => {
        properties => {
            parents => {
                isa => $mapper->relation(
                    'many_to_many' => $association => 'MyTest14::Parent',
                    { cascade => 'all' }
                )
            }
        }
    }
);

subtest 'cascade_save' => sub {
    my $session = $mapper->begin_session( autocommit => 0 );
    ok my $parent = MyTest14::Parent->new( id => 1 );

    for( 1 .. 5 ) {
        push @{$parent->children}, MyTest14::Child->new( id => $_  );
    }
    $session->add($parent);

    $session->flush;
    $session->commit;

    # check
    my $check_parent = $session->get( 'MyTest14::Parent' => 1 );
    is @{$check_parent->children}, 5;

    done_testing;
};

subtest 'cascade_update' => sub {
    my $session = $mapper->begin_session( autocommit => 0 );
    ok my $parent = $session->get( 'MyTest14::Parent' => 1 );
    $parent->id(10);
    $session->commit;

    # check
    ok my $check_parent = $session->get( 'MyTest14::Parent' => 10 );
    is @{$check_parent->children}, 5;

    done_testing;
};

subtest 'add' => sub {
    my $session = $mapper->begin_session( autocommit => 0 );
    ok my $p = $session->get( 'MyTest14::Parent' => 10 );
    is $p->id, 10;
    ok $p->children;
    is ref($p->children), 'ARRAY';
    is scalar(@{$p->children}), 5;
    for my $c ( @{$p->children} ) {
        ok $c->id;
    }

    push @{$p->children}, MyTest14::Child->new( id => 6 );
    $session->commit;

    # check
    ok my $check = $session->get( 'MyTest14::Parent' => 10 );
    is scalar(@{$check->children}), 6;

    done_testing;
};

subtest 'remove' => sub {
    my $session = $mapper->begin_session( autocommit => 0 );
    ok my $p = $session->get( 'MyTest14::Parent' => 10 );
    is $p->id, 10;
    ok $p->children;
    is ref($p->children), 'ARRAY';
    is scalar(@{$p->children}), 6;

    shift @{$p->children};
    $session->commit;

    # check
    ok my $check = $session->get( 'MyTest14::Parent' => 10 );
    is scalar(@{$check->children}), 5;

    done_testing;
};

subtest 'cascade_delete' => sub {
    my $session = $mapper->begin_session( autocommit => 0 );
    ok my $p = $session->get( 'MyTest14::Parent' => 10 );
    my @child_ids = map { $_->id } @{$p->children};
    $session->delete($p);
    $session->commit;

    # check
    ok !$session->get( 'MyTest14::Parent' => 10 );
    ok $association->select->where( $association->c('left_id') == 10 )->count == 0;
    for my $cid ( @child_ids ) {
        ok $session->get( 'MyTest14::Child' => $cid );
    }

    done_testing;
};

subtest 'eagerload' => sub {
    plan skip_all => 'TODO';
};

done_testing;
