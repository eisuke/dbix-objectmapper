use strict;
use warnings;
use Test::More;

use Data::ObjectMapper::Metadata;
use Data::ObjectMapper::Engine::DBI;
use Data::ObjectMapper::Mapper;

use FindBin;
use File::Spec;
use lib File::Spec->catfile( $FindBin::Bin, 'lib' );

my $engine = Data::ObjectMapper::Engine::DBI->new({
    dsn => 'DBI:SQLite:',
    username => '',
    password => '',
    on_connect_do => [
        q{ CREATE TABLE artist (id integer primary key, firstname text not null, lastname text not null)}
    ]
});

my $meta = Data::ObjectMapper::Metadata->new( engine => $engine );
my $artist_table = $meta->table(
    artist => { autoload_column => 1 }
);

$artist_table->insert->values(
    firstname => 'a1',
    lastname => 'b1'
)->execute;

$artist_table->insert->values(
    firstname => 'a2',
    lastname => 'b2'
)->execute;

$artist_table->insert->values(
    firstname => 'a3',
    lastname => 'b3'
)->execute;

{
    use MyTest::Basic::Artist;
    ok my $mapper = Data::ObjectMapper::Mapper->new(
        $artist_table => 'MyTest::Basic::Artist'
    );
    $mapper->mapping;

    for my $c ( @{$artist_table->columns} ) {
        is_deeply $mapper->attributes_config->{$c->name}{isa}, $c;
    }

    my $session = Data::ObjectMapper->session;

    my $artist = $mapper->session('MyTest::Basic::Artist')->find(1);

    is $artist->firstname, 'a1';
    is $artist->lastname, 'b1';
    is $artist->fullname, 'a1 b1';

    $artist->firstname('a1-2');
    $artist->lastname('b1-2');
    is $artist->fullname, 'a1-2 b1-2';

    $mapper->save($artist);

    require Data::Dumper;
    print Data::Dumper::Dumper($artist);
};



done_testing;

__END__

{
    package My::Artist;
    use strict;
    use warnings;

    1;
};

{


    my $mapped_artist = maps (
        $meta->t('artist') => 'My::Artist',
        #include_property => [] | '*',
        #exclude_property => [],
        #propery_prefix => '_'
        property => {
            code => {
                isa => $meta->t('artist')->c('id'),
                lazy => 1,
                gen_accessor => 1,
                getter => sub { $_[0]->param('a') },
                validation => 1,
                coarce => 1,
                validation_method => '_validate_id',
            },
        },
        #constructor => 'new'
        #argument => 'HASHREF',
        #generate_accessor => 1
        #default_condition => [ $meta->t(artist)->c('type') == 'person' ]
    );
};

__END__

{
    my $session = Data::ObjectMapper::Session->new({ engine => $engine} );


    my $call_obj = $session->query('My::TestTable')->find(1);
    my $new_obj = My::TestTable->new({ name => 'hoge' });
    $session->save($new_obj);


    my $meta1 = $db->metadata([]);
    $meta1->map_to('My::Obj', { });

    $db->meta->users;

    my $meta2 = $db->metadata([]);
    $meta2->map_to('My::Obj2');

    $db->map_all('My::');

    my $find_ojb = $db->session->query('My::Obj2')->find(1);

    my $new_obj = My::Obj->new({ name => 'hoge' });
    $db->save($new_obj);

    my $it = $db->session->query('My::Obj')->join('My::Obj2')->filter(
        $db->meta->users->name == 1,
        $db->meta->users->active == 1,
    )->yaml;

    while( $it->next ) {

    }

};
