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
            q{CREATE TABLE parent (id integer primary key, name text)},
            q{CREATE TABLE child (id integer primary key, parent_id integer REFERENCES parent(id), name text)},
        ]
    }),
);

$mapper->metadata->autoload_all_tables;

ok $mapper->maps(
    $mapper->metadata->t('parent') => 'Parent',
    constructor => +{ auto => 1 },
    accessors   => +{ auto => 1 },
    attributes  => +{
        properties => +{
            children => +{
                isa => $mapper->relation(
                    has_many => 'Child',
                ),
            }
        }
    }
);

ok $mapper->maps(
    $mapper->metadata->t('child') => 'Child',
    constructor => +{ auto => 1 },
    accessors   => +{ auto => 1 },
    attributes  => +{
        properties => +{
            parent => +{
                isa => $mapper->relation(
                    belongs_to => 'Parent',
                    { cascade => 'save_update,delete' }
                )
            }
        }
    },
);

{
    my $session = $mapper->begin_session;
    my @child = map{ Child->new( name => 'child' . $_ ) } 1 .. 5;
    my $parent = Parent->new( id => 1, name => 'parent1' );
    $_->parent($parent) for @child;
    $session->add_all(@child);
    $session->commit;
    ok 'done';
};

{
    my $session = $mapper->begin_session;

    my $it = $session->search('Child')->execute;
    my $loop_cnt = 0;
    while( my $c = $it->next ) {
        ok $c->id;
        is $c->parent_id, 1;
        ok $c->parent;
        is $c->parent->id, 1;
        $loop_cnt++;
    }
    is $loop_cnt, 5;
};

{
    my $session = $mapper->begin_session( autocommit => 0, autoflush => 1 );
    my @child = map{ Child->new( name => 'child' . $_ ) } 6 .. 10;
    my $parent = Parent->new( id => 2, name => 'parent2' );
    $session->add($parent);
    $_->parent($parent) for @child;
    $session->add_all(@child);
    $session->commit;
    ok 'done';
};

{
    my $session = $mapper->begin_session;

    my $it = $session->search('Child')->execute;
    my $loop_cnt = 0;
    while( my $c = $it->next ) {
        ok $c->id;
        ok $c->parent;
        if( $c->id > 5 ) {
            is $c->parent->id, 2;
        }
        else {
            is $c->parent->id, 1;
        }
        $loop_cnt++;
    }
    is $loop_cnt, 10;
};


{
    my $session = $mapper->begin_session( autocommit => 0 );
    $session->get( 'Parent' => 1 );
    my $c1 = $session->get( 'Child' => 1 );
    $session->delete($c1);
    $session->commit;
    ok !$session->get( 'Parent' => 1 );

    # 1 child deleted. and others, parent_id is null
    my $child_attr = $mapper->attribute('Child');
    my $children = $session->search('Child')->filter(
        $child_attr->p('parent_id') == undef
    )->execute;
    is @$children, 4;

    ok 'done';
};

ok $mapper->maps(
    $mapper->metadata->t('parent') => 'Parent2',
    constructor => +{ auto => 1 },
    accessors   => +{ auto => 1 },
    attributes  => +{
        properties => +{
            children => +{
                isa => $mapper->relation(
                    has_many => 'Child2',
                    { cascade => 'all' },
                ),
            }
        }
    }
);

ok $mapper->maps(
    $mapper->metadata->t('child') => 'Child2',
    constructor => +{ auto => 1 },
    accessors   => +{ auto => 1 },
    attributes  => +{
        properties => +{
            parent => +{
                isa => $mapper->relation(
                    belongs_to => 'Parent2',
                    { cascade => 'save_update,delete' }
                )
            }
        }
    },
);

{
    my $session = $mapper->begin_session;
    my @child = map{ Child2->new( name => 'child' . $_ ) } 11 .. 15;
    my $parent = Parent2->new( id => 3, name => 'parent3' );
    $_->parent($parent) for @child;
    $session->add_all(@child);
    $session->commit;
    ok 'done';
};

{
    my $session = $mapper->begin_session( autocommit => 0 );
    $session->get( 'Parent2' => 3 );
    my $c11 = $session->get( 'Child2' => 11 );
    $session->delete($c11);
#    $session->commit;

    ok !$session->get( 'Parent2' => 3 );

    # all children deleted.
    my $child_attr = $mapper->attribute('Child2');
    my $children = $session->search('Child2')->filter(
        $child_attr->p('parent_id') == 3
    )->execute;
    is @$children, 0;

    ok 'done';
};

{
    my $session = $mapper->begin_session( autocommit => 0 );
    my $p = $session->get( 'Parent2' => 3 );
    $session->detach($p);
    ok 'done';
};

done_testing;

