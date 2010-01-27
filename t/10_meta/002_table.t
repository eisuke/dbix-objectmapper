use strict;
use warnings;
use Test::More qw(no_plan);
use Data::ObjectMapper::Engine::DBI;

use Data::ObjectMapper::Metadata::Table;
use Data::ObjectMapper::Metadata::Sugar qw(:all);

{
    my $inflate = sub{ 'inflate' };
    my $deflate = sub{ 'deflate' };

    ok my $meta = Data::ObjectMapper::Metadata::Table->new(
        testmetadata => [
            Col( id      => Int(), PrimaryKey, Readonly ),
            Col( name    => Text(undef, utf8 => 1), NotNull ),
            Col( cd      => String(3), NotNull, Unique ),
            Col( r       => SmallInt(), NotNull, ForeignKey( 'refs' => 'col') ),
            Col( created => DateTime(), Default{ time() }, Validation{ 1 } ),
            Col( updated => DateTime(), OnUpdate{ time() } ),
        ],
        {
            unique_key      => [ 'name_uniq' => ['name'] ],
            foreign_key     => [
                {
                    keys  => ['name'],
                    table => 'test',
                    refs  => ['id']
                }
            ],
            readonly => ['id'],
            utf8     => ['name'],
            default  => { name => sub{ 'default' } },
            coerce   => {
                name => {
                    to_storage   => $inflate,
                    from_storage => $deflate,
                },
            },
            validation => { name => sub{ 1 } , }
        }
    );

    is $meta->table_name, 'testmetadata';
    is_deeply $meta->primary_key, [qw(id)];
    is_deeply [ map { $_->name } @{ $meta->columns } ],
        [qw(id name cd r created updated)];
    ok my $id = $meta->c('id');
    is ref($id->type), 'Data::ObjectMapper::Metadata::Table::Column::Type::Int';
    is_deeply $meta->unique_key('name_uniq'), ['name'];
    is_deeply $meta->unique_key('c_uniq_cd'), ['cd'];
    is_deeply $meta->utf8, [ 'name' ];

    ok $meta->c('name')->type->utf8;
    is ref($meta->default->{$_}), 'CODE' for qw(name created);

    ok $meta->coerce->{name};
    is ref($meta->coerce->{name}{to_storage}), 'CODE';
    is ref($meta->coerce->{name}{from_storage}), 'CODE';

    is ref($meta->validation->{$_}), 'CODE' for qw(name created);


    is_deeply $meta->foreign_key, [
        {
            keys  => ['name'],
            table => 'test',
            refs  => ['id']
        },
        {
            keys => ['r'],
            table => 'refs',
            refs => ['col'],
        }
    ];

    is_deeply $meta->get_foreign_key_by_col('name'), [
        {
            keys  => ['name'],
            table => 'test',
            refs  => ['id']
        },
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

    ok my $meta = Data::ObjectMapper::Metadata::Table->new(
        testmetadata => [
            Col( name => Text(undef, utf8 => 1) ),
            Col( created => Default { time() } ),
            Col( updated => OnUpdate { time() }),
        ],
        {
            engine => $engine,
            autoload => 1,
        }
    );

    ok $meta->c('id');
    ok $meta->c('name');
    ok $meta->c('name')->{type}->utf8;
    ok $meta->c('created');
    is $meta->c('created')->{type}->realtype, 'timestamp';
    is ref($meta->c('created')->default), 'CODE';
    ok $meta->c('updated');
    is ref($meta->c('updated')->on_update), 'CODE';

    ok my $meta2 = Data::ObjectMapper::Metadata::Table->new(
        testfk => 'autoload',
        { engine => $engine }
    );

    is_deeply $meta2->foreign_key, [
        {   refs  => ['id'],
            table => 'testmetadata',
            keys  => ['pid']
        }
    ];

};
