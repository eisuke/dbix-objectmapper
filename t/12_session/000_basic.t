use strict;
use warnings;
use Test::More;

use Data::ObjectMapper::Session;

use FindBin;
use File::Spec;
use lib File::Spec->catfile( $FindBin::Bin, 'lib' );
use MyTest11;

my $engine = MyTest11->engine;
MyTest11->setup_default_data;

{ # find
    my $session = Data::ObjectMapper::Session->new();

    my @artists;
    ok my $artist = $session->query('MyTest11::Artist')->find(1);
    push @artists, $artist;
    ok my $artist2 = $session->query('MyTest11::Artist')->find({ id => 1 });
    push @artists, $artist2;

    for my $a ( @artists ) {
        is ref $a, 'MyTest11::Artist';
        is $a->name, 'Led Zeppelin';
        is $a->id, 1;
    }

    ok $artist->name('レッドツェッペリン');

    $session->save($artist);
};



done_testing;
__END__

{
    my $session = Data::ObjectMapper::Session->new({ engine => $engine });

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

