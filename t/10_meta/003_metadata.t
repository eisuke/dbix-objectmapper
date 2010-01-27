use strict;
use warnings;
use Test::More qw(no_plan);
use Data::ObjectMapper::Metadata;
use Data::ObjectMapper::Metadata::Sugar qw(:all);
use Data::ObjectMapper::Engine::DBI;

{
    ok my $metadata = Data::ObjectMapper::Metadata->new;

    ok my $person = $metadata->table(
        'person' => [
            Col( id => Int(), PrimaryKey ),
            Col( name => Text(), NotNull ),
        ],
    );

    ok $metadata->table('person');
    ok $metadata->t('person');

    ok $person->c('name');
    ok $person->c('id');
    ok $metadata->t('person')->c('name');
};

{
    my $engine = Data::ObjectMapper::Engine::DBI->new({
        dsn => 'DBI:SQLite:',
        username => '',
        password => '',
        on_connect_do => [
            q{ CREATE TABLE testmetadata (id integer primary key, name text, created timestamp, updated timestamp)},
            q{ CREATE TABLE testmetadata2 (id integer primary key)},
            q{ CREATE TABLE testmetadata3 (id integer primary key)},
        ],
    });

    my $meta = Data::ObjectMapper::Metadata->new( engine => $engine );
    my @tables = $meta->autoload_all_tables;
    is_deeply \@tables, [qw(testmetadata testmetadata2 testmetadata3)];
    ok my $test = $meta->t('testmetadata');
    ok $test->c('id');
    ok $test->c('name');
    ok $test->c('created');
    ok $test->c('updated');

};

