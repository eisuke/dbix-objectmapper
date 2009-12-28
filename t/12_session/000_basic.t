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
    ok my $artist = $session->get( 'MyTest11::Artist' => 1 );
    push @artists, $artist;
    is $artist->__mapper__->status, 'persistent';

    ok my $artist2 = $session->get( 'MyTest11::Artist' => { id => 1 } );
    push @artists, $artist2;
    is $artist2->__mapper__->status, 'persistent';

    for my $a ( @artists ) {
        is ref $a, 'MyTest11::Artist';
        is $a->name, 'Led Zeppelin';
        is $a->id, 1;
    }

    ok $artist->name('レッドツェッペリン');
    ok $artist->__mapper__->is_modified;
    is $artist->name, 'レッドツェッペリン';
};

{
    my $session = Data::ObjectMapper::Session->new();
    ok my $artist = $session->get( 'MyTest11::Artist' => 1 );
    is $artist->name, 'レッドツェッペリン';
    is $artist->__mapper__->status, 'persistent';
};

{
    my $session = Data::ObjectMapper::Session->new();
    my $obj = MyTest11::Artist->new( name => 'Jimi Hendrix' );
    ok $session->add($obj);
    is $obj->__mapper__->status, 'pending';
    $session->flush;
    is $obj->__mapper__->status, 'expired';
    is $obj->name, 'Jimi Hendrix';
    is $obj->__mapper__->status, 'persistent';
    $obj->name('じみへん');
    $session->flush();
    is $obj->__mapper__->status, 'expired';
    my $name = $obj->name;
    $obj->name('jimihen');
    is $obj->__mapper__->status, 'persistent';
};

{
    my $session = Data::ObjectMapper::Session->new();
    ok my $artist = $session->get( 'MyTest11::Artist' => 2 );
    is $artist->id, 2;
    is $artist->name, 'jimihen';
    is $artist->__mapper__->status, 'persistent';
    $session->detach($artist);
    is $artist->__mapper__->status, 'detached';
};

{
    my $session = Data::ObjectMapper::Session->new();
    ok my $artist = $session->get( 'MyTest11::Artist' => 2 );
    $artist->id(3);
    $session->flush;

    ok my $artist3 = $session->get( 'MyTest11::Artist' => 3 );
    is $artist3->name, 'jimihen';
    ok $session->delete($artist3);
    is $artist3->__mapper__->status, 'detached';
};

done_testing;
__END__
