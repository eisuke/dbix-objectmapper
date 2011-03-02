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
            q{CREATE TABLE cd (id integer primary key)},
            q{CREATE TABLE linernote (id integer primary key, note TEXT)},
        ]
    }),
);

$mapper->metadata->autoload_all_tables;
$mapper->metadata->t('cd')->insert->values(id => $_)->execute() for 1 .. 2;
$mapper->metadata->t('linernote')->insert->values({id => 1, note => 'aaa' })->execute();

$mapper->maps(
    $mapper->metadata->t('cd') => 'MyTest35::CD',
    constructor => +{ auto => 1 },
    accessors   => +{ auto => 1 },
    attributes  => +{
        properties => +{
            linernote => +{
                isa => $mapper->relation(
                    has_one => 'MyTest35::Linernote',
                    { cascade => 'reflesh_expire' },
                ),
            }
        }
    }
);

$mapper->maps(
    $mapper->metadata->t('linernote') => 'MyTest35::Linernote',
    constructor => +{ auto => 1 },
    accessors   => +{ auto => 1 },
);

{
    my $session = $mapper->begin_session;
    ok my $cd1 = $session->get( 'MyTest35::CD' => 1 );
    ok $cd1->linernote->note, 'aaa';
    $mapper->metadata->t('linernote')->update({ note => 'bbb' })->where( $mapper->metadata->t('linernote')->c('id') == 1 )->execute;
    $session->refresh($cd1);
    ok $cd1->linernote;
    is $cd1->linernote->note, 'bbb';
};

{
    my $session = $mapper->begin_session;
    ok my $cd2 = $session->get( 'MyTest35::CD' => 2 );
    ok !$cd2->linernote;
    $mapper->metadata->t('linernote')->insert->values({id => 2, note => 'ccc' })->execute();
    ok !$cd2->linernote;
    $session->refresh($cd2);
    ok $cd2->linernote;
    is $cd2->linernote->note, 'ccc';
};

done_testing;
