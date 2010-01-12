use strict;
use warnings;
use Test::More;

use Data::ObjectMapper;
use Data::ObjectMapper::Engine::DBI;

my $mapper = Data::ObjectMapper->new(
    engine => Data::ObjectMapper::Engine::DBI->new({
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
$mapper->metadata->t('parent')->insert->values(id => 1)->execute();
$mapper->metadata->t('child')->insert->values({parent_id => 1})->execute() for 0 .. 4;

ok $mapper->maps(
    $mapper->metadata->t('parent') => 'Parent',
    constructor => +{ auto => 1 },
    accessors   => +{ auto => 1 },
    attributes  => +{
        properties => +{
            children =>
                +{ isa => $mapper->relation( has_many => 'Child' ), }
            }
    }
);

ok $mapper->maps(
    $mapper->metadata->t('child') => 'Child',
    constructor => +{ auto => 1 },
    accessors   => +{ auto => 1 },
    attributes  => +{
        properties => +{
            parent =>
                +{ isa => $mapper->relation( belongs_to => 'Parent' ) }
            }
    },
);

{
    my $session = $mapper->begin_session;
    my $parent = $session->get( Parent => 1 ); # query_cnt++

    is ref($parent->children), 'ARRAY'; # query_cnt++
    for my $c ( @{$parent->children} ) {
        is $c->parent_id, $parent->id;
    }

    my $child1 = $session->get( Child => 4 );
    is $child1->parent->id, 1;
    my $child_child = $child1->parent->children;
    is $child_child->[0]->parent->id, 1; # query_cnt++
    is $child_child->[0]->parent->children->[3]->parent->id, 1; # query_cnt++
    is $session->uow->query_cnt, 4;
};


done_testing;

__END__

{ # eager_load
    my $session = $mapper->begin_session;
    my $parent = $session->get(
        Parent => 1,
        { eagerload => 'children' }
    );

#    is ref($parent->children), 'ARRAY';
#    for my $c ( @{$parent->children} ) {
#        is $c->parent_id, $parent->id;
#    }
};


{ # nest join
    my $session = $mapper->begin_session;
    my $it
        = $session->query( 'MyTest11::Artist', { eager_load => 1 } )
        ->join( { 'MyTest::Cd' => ['MyTest::Track'] } )
        ->order_by( $artist->c('id')->desc )->execute;

};