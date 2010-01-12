use strict;
use warnings;
use Test::More;
use File::Spec;
use FindBin;
use lib File::Spec->catfile($FindBin::Bin, 'lib');
use MyTest11;

#use Devel::Leak::Object  qw{ GLOBAL_bless };
#$Devel::Leak::Object::TRACKSOURCELINES = 1;

MyTest11->setup_default_data;
my $mapper = MyTest11->mapper;

{ # has_many
    my $session = $mapper->begin_session;
    my $artist = $mapper->metadata->t('artist');
    my $cd     = $mapper->metadata->t('cd');
    my $it = $session->query('MyTest11::Artist')->join('cds')
        ->where( $cd->c('title')->like('Led Zeppelin%') )->execute;
    ok $it;

    my $loop_cnt = 0;
    while( my $a = $it->next ) {
        $loop_cnt++;
        is $a->id, 1;
        is $a->name, 'Led Zeppelin';
    }
    is $loop_cnt, 1;
};

{ # belongs_to
    my $session = $mapper->begin_session;
    my $artist = $mapper->metadata->t('artist');
    my $cd     = $mapper->metadata->t('cd');
    my $it = $session->query('MyTest11::Cd')->join('artist')
        ->where(
            $artist->c('name') == 'Led Zeppelin',
            $cd->c('title')->like('Led Zeppelin%')
        )->execute;
    ok $it;
    my $loop_cnt = 0;
    while( my $a = $it->next ) {
        $loop_cnt++;
    }
    is $loop_cnt, 4;
};

{ # eargerload
    my $session = $mapper->begin_session;
    my $artist = $mapper->metadata->t('artist');
    my $cd     = $mapper->metadata->t('cd');
    my $it = $session->query(
        'MyTest11::Artist',
        { eagerload => 1 }
    )->join('cds')
     ->where( $cd->c('title')
     ->like('Led Zeppelin%') )
     ->order_by( )
     ->execute;
    ok $it;

    my $loop_cnt = 0;
    while( my $a = $it->next ) {
        $loop_cnt++;
        require Data::Dump;
        warn Data::Dump::dump($a);
    }
    is $loop_cnt, 1;

};


done_testing;

__END__

{ # eager_load
    my $session = $mapper->begin_session;
    my $artist = $session->get(
        'MyTest11::Artist' => 1,
        { eagerload => 'MyTest11::Cd' }
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
