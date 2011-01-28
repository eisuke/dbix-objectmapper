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
            q{CREATE TABLE parent (id integer primary key)},
            q{CREATE TABLE child (id integer primary key, parent_id integer REFERENCES parent(id), seq INTEGER NOT NULL, UNIQUE(parent_id, seq) )},
        ]
    }),
);

$mapper->metadata->autoload_all_tables;
$mapper->metadata->t('parent')->insert->values(id => 1)->execute();
$mapper->metadata->t('parent')->insert->values(id => 2)->execute();

$mapper->metadata->t('child')->insert->values({parent_id => 1, seq => $_ })->execute() for 1 .. 4;
$mapper->metadata->t('child')->insert->values({parent_id => 2, seq => $_ })->execute() for 1 .. 2;

$mapper->maps(
    $mapper->metadata->t('parent') => 'MyTest::Parent',
    constructor => +{ auto => 1 },
    accessors   => +{ auto => 1 },
    attributes  => +{
        properties => +{
            children => +{
                isa => $mapper->relation(
                    has_many => 'MyTest::Child',
#                    { cascade => 'delete_orphan' },
                ),
            }
        }
    }
);

$mapper->maps(
    $mapper->metadata->t('child') => 'MyTest::Child',
    constructor => +{ auto => 1 },
    accessors   => +{ auto => 1 },
);


treat_orphan();
move_has_many();
{
    my $prop = MyTest::Parent->__class_mapper__->attributes->property_info('children')->{isa};
    local $prop->{cascade}{delete_orphan} = 1;
    treat_orphan(1);
    move_has_many(1);
};

sub treat_orphan {
    my $delete_orphan = shift;

    my $session = $mapper->begin_session( no_cache => 1 );
    my $p1 = $session->get( 'MyTest::Parent' => 1 );
    my $p2 = $session->get( 'MyTest::Parent' => 2 );

    my $child = shift(@{$p1->children});
    my $child_id = $child->id;
    $session->commit;

    $session = $mapper->begin_session( no_cache => 1 );
    my $child_check = $session->get( 'MyTest::Child' => $child_id );
    if( $delete_orphan ) {
        ok !$child_check;
    }
    else {
        ok $child_check;
        is $child_check->parent_id, undef;
    }
}

sub move_has_many {
    my $delete_orphan = shift;

    my $session = $mapper->begin_session( no_cache => 1 );
    my $p1 = $session->get( 'MyTest::Parent' => 1 );
    my $p2 = $session->get( 'MyTest::Parent' => 2 );

    my $child = shift(@{$p1->children});
    my $child_id = $child->id;
    my @p2_sort_seq = sort { $a->seq <=> $b->seq } @{$p2->children};

    $child->seq( $p2_sort_seq[$#p2_sort_seq]->seq + 1 );
    push @{$p2->children}, $child;

    $session->commit;
    my $child_check = $session->get( 'MyTest::Child' => $child_id );
    is $child_check->parent_id, 2;
    # delete_orphanでもdeleteされないでupdateされる
    is $child_check->id, $child_id;
}

done_testing;
