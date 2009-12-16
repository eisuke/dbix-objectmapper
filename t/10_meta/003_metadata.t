use strict;
use warnings;
use Test::More qw(no_plan);
use Data::ObjectMapper::Metadata;
use Data::ObjectMapper::Engine::DBI;

{
    ok my $metadata = Data::ObjectMapper::Metadata->new;

    ok my $person = $metadata->table(
        'person' => {
            primary_key => ['id'],
            column      => [
                {   name        => 'id',
                    type        => 'integer',
                    is_nullable => 0,
                },
                {   name        => 'name',
                    type        => 'text',
                    is_nullable => 0,
                },
            ],
        }
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
            q{ CREATE TABLE testmetadata (id integer primary key, name text, created timestamp, updated timestamp)}
        ],
    });

    my $meta = Data::ObjectMapper::Metadata->new( engine => $engine );

    ok my $test = $meta->table(
        testmetadata => {
            autoload_column => 1,
        }
    );

    ok $test->c('id');
    ok $test->c('name');
    ok $test->c('created');
    ok $test->c('updated');

};

