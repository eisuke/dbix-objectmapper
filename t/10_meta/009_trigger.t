use strict;
use warnings;
use Test::More;
use DBIx::ObjectMapper::Metadata;
use DBIx::ObjectMapper::Engine::DBI;

my $engine = DBIx::ObjectMapper::Engine::DBI->new({
    dsn => 'DBI:SQLite:',
    username => '',
    password => '',
    on_connect_do => [
        q{CREATE TABLE artist( id integer primary key, name text, name2 text )},
    ],
});

my $meta = DBIx::ObjectMapper::Metadata->new( engine => $engine );

my %trigger_cnt = (
    before_insert => 0,
    after_insert  => 0,
    before_update => 0,
    after_update  => 0,
    before_delete => 0,
    after_delete  => 0,
);

my $artist = $meta->t(
    'artist' => 'autoload',
    {
        before_insert => sub {
            my ( $metadata, $builder, $table ) = @_;
            is ref($metadata), 'DBIx::ObjectMapper::Metadata';
            is ref($builder), 'DBIx::ObjectMapper::SQL::Insert';
            is_deeply $builder->values, { name => 'name1' };
            is $table, 'artist';
            $trigger_cnt{before_insert}++;
        },
        after_insert  => sub {
            my ( $metadata, $insert_data, $table ) = @_;
            is ref($metadata), 'DBIx::ObjectMapper::Metadata';
            is_deeply $insert_data, { id => 1, name => 'name1' };
            is $table, 'artist';
            $trigger_cnt{after_insert}++;
        },
        before_update => sub {
            my ( $metadata, $builder, $table ) = @_;
            is ref($metadata), 'DBIx::ObjectMapper::Metadata';
            is ref($builder), 'DBIx::ObjectMapper::SQL::Update';
            is_deeply $builder->set, { name => 'name-hoge' };
            is $table, 'artist';
            $trigger_cnt{before_update}++;
        },
        after_update  => sub {
            my ( $metadata, $update_cnt, $table ) = @_;
            is ref($metadata), 'DBIx::ObjectMapper::Metadata';
            is $update_cnt, 1;
            is $table, 'artist';
            $trigger_cnt{after_update}++;
        },
        before_delete => sub {
            my ( $metadata, $builder, $table ) = @_;
            is ref($metadata), 'DBIx::ObjectMapper::Metadata';
            is ref($builder), 'DBIx::ObjectMapper::SQL::Delete';
            is $table, 'artist';
            $trigger_cnt{before_delete}++;
        },
        after_delete  => sub {
            my ( $metadata, $delete_cnt, $table ) = @_;
            is ref($metadata), 'DBIx::ObjectMapper::Metadata';
            is $delete_cnt, 1;
            is $table, 'artist';
            $trigger_cnt{after_delete}++;
        },
    },
);

is $trigger_cnt{before_insert}, 0;
is $trigger_cnt{after_insert}, 0;
$artist->insert( name => 'name1' )->execute;
is $trigger_cnt{before_insert}, 1;
is $trigger_cnt{after_insert}, 1;

is $trigger_cnt{before_update}, 0;
is $trigger_cnt{after_update}, 0;
$artist->update({ name => 'name-hoge'})->execute;
is $trigger_cnt{before_update}, 1;
is $trigger_cnt{after_update}, 1;

is $trigger_cnt{before_delete}, 0;
is $trigger_cnt{after_delete}, 0;
$artist->delete->execute;
is $trigger_cnt{before_delete}, 1;
is $trigger_cnt{after_delete}, 1;

SKIP: {
    eval "require Test::Memory::Cycle";
    if ($@) {
        skip("Error requiring Test::Memory::Cycle: $@", 2);
    }

    # Versions of Devel::Cycle less than 1.09 had a bug when looking at
    # closed-over variables in coderefs: Devel::Cycle attempted to dereference
    # all such variables as scalar references.  This dies when, for example,
    # the variable is a hashref.  Skip these tests if Devel::Cycle is an
    # earlier version.
    if (Devel::Cycle->VERSION lt '1.09') {
        skip("Skipped memory cycle test because your version (" . Devel::Cycle->VERSION. ") of Devel::Cycle is ancient and buggy", 2);
    }

    Test::Memory::Cycle::memory_cycle_ok( $artist );
    Test::Memory::Cycle::memory_cycle_ok( $meta );
};

done_testing;
