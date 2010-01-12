use strict;
use warnings;
use Test::More qw(no_plan);
use Data::ObjectMapper::Engine::DBI;

BEGIN{ use_ok('Data::ObjectMapper::Metadata::Table') }


{
    my $now = sub { time() };
    my $inflate = sub{ 'inflate' };
    my $deflate = sub{ 'deflate' };
    my $validation = sub{ 1 };

    ok my $meta = Data::ObjectMapper::Metadata::Table->new(
        testmetadata => {
            primary_key => ['id'],
            column      => [
                {   name        => 'id',
                    type        => 'integer',
                    is_nullable => 1,
                    size        => 8,
                },
                {   name        => 'name',
                    type        => 'text',
                    is_nullable => 1,
                    size        => 10000,
                },
                {   name        => 'created',
                    type        => 'timestamp',
                    is_nullable => 1,
                    size        => '30',
                    default     => $now,
                    validation  => $validation,
                },
                {   name        => 'updated',
                    type        => 'timestamp',
                    is_nullable => 1,
                    size        => '30',
                    on_update   => $now,
                },
            ],
            unique_key      => [ 'name_uniq' => ['name'] ],
            foreign_key     => [
                {
                    keys  => ['name'],
                    table => 'test',
                    refs  => ['id']
                }
            ],
            temp_column     => ['memo'],
            readonly_column => ['id'],
            utf8_column     => ['name'],
            column_default  => { name        => 'default' },
            column_coerce   => {
                name => {
                    inflate => $inflate,
                    deflate => $deflate,
                },
            },
            column_validation => { name => $validation, }
        }
    );

    is $meta->table_name, 'testmetadata';
    is_deeply $meta->primary_key, [qw(id)];
    is_deeply [ map { $_->name } @{ $meta->columns } ],
        [qw(id name created updated)];
    ok my $id = $meta->c('id');
    is $id->size, 8;
    is $id->type, 'integer';
    is_deeply $meta->unique_key('name_uniq'), ['name'];
    is_deeply $meta->temp_column, ['memo'];
    is_deeply $meta->utf8_column, [ 'name' ];

    ok $meta->c('name')->utf8;
    is_deeply $meta->column_default, { name => 'default', created => $now };
    is_deeply $meta->column_coerce, {
        name => { inflate => $inflate, deflate => $deflate },
    };

    is_deeply $meta->column_validation, {
        name => $validation,
        created => $validation,
    };

    is_deeply $meta->foreign_key, [
        {
            keys  => ['name'],
            table => 'test',
            refs  => ['id']
        }
    ];

    is_deeply $meta->get_foreign_key_by_col('name'), [
        {
            keys  => ['name'],
            table => 'test',
            refs  => ['id']
        }
    ];
};

{
    my $engine = Data::ObjectMapper::Engine::DBI->new({
        dsn => 'DBI:SQLite:',
        username => '',
        password => '',
        on_connect_do => [
            q{ CREATE TABLE testmetadata (id integer primary key, name text, created timestamp, updated timestamp)},
            q{ CREATE TABLE testfk (id interger primary key, pid integer references testmetadata(id))},
        ],
    });

    my $now = sub{ time() };

    ok my $meta = Data::ObjectMapper::Metadata::Table->new(
        testmetadata => {
            engine => $engine,
            autoload_column => 1,
            column => [
                {
                    name => 'name',
                    utf8 => 1,
                },
                {
                    name => 'created',
                    default => $now,
                },
                {
                    name => 'updated',
                    on_update => $now,
                },
            ],
        }
    );

    ok $meta->c('id');
    ok $meta->c('name');
    ok $meta->c('name')->utf8;
    ok $meta->c('created');
    is $meta->c('created')->default, $now;
    ok $meta->c('updated');
    is $meta->c('updated')->on_update, $now;

    ok my $meta2 = Data::ObjectMapper::Metadata::Table->new(
        testfk => {
            engine => $engine,
            autoload_column => 1,
        }
    );

    is_deeply $meta2->foreign_key, [
        {   refs  => ['id'],
            table => 'testmetadata',
            keys  => ['pid']
        }
    ];

};
