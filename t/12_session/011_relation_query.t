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
     )
     ->eager_join('cds')
     ->where( $cd->c('title')->like('Led Zeppelin%') )
     ->order_by( $cd->c('id')->desc )
     ->execute;
    ok $it;
    my $loop_cnt = 0;
    my $cd_id = 4;
    while( my $a = $it->next ) {
        $loop_cnt++;
        is $a->id, 1;
        is $a->name, 'Led Zeppelin';
        for my $cd ( @{$a->cds} ) {
            is $cd->id, $cd_id--;
        }
    }
    is $loop_cnt, 1;
};

{ # nest join
    my $session = $mapper->begin_session;
    my $artist = $mapper->metadata->t('artist');
    my $cd     = $mapper->metadata->t('cd');
    my $track  = $mapper->metadata->t('track');
    my $it = $session->query('MyTest11::Artist')->join(
        { 'cds' => 'tracks' },
    )->where(
        $cd->c('title')->like('Led Zeppelin%'),
        $track->c('track_no') > 8,
    )->execute;

    my $loop_cnt = 0;
    while( my $a = $it->next ) {
        $loop_cnt++;
        is $a->id, 1;
        is $a->name, 'Led Zeppelin';
    }

    is $loop_cnt, 1;
};

{ # nest join eagerload
    my $session = $mapper->begin_session;
    my $artist = $mapper->metadata->t('artist');
    my $cd     = $mapper->metadata->t('cd');
    my $track  = $mapper->metadata->t('track');
    my $it
        = $session->query( 'MyTest11::Artist' )
        ->eager_join( { 'cds' => 'tracks' } )->where(
        $cd->c('title')->like('Led Zeppelin%'),
        $track->c('track_no') > 8,
        )->execute;
    my $loop_cnt = 0;
    while( my $a = $it->next ) {
        $loop_cnt++;
        is $a->id, 1;
        is $a->name, 'Led Zeppelin';
        ok $a->cds;
        # ******* memo **********
        # eagerloadは第一階層までにしておく
        # そもそも深い階層のeagerloadは重いので、
        # こそまで必要であれば、metadata.queryを利用したほうがいいと思う
        # ***********************
        ok $a->cds->[0]->tracks;
    }

    is $loop_cnt, 1;
    is $session->uow->query_cnt, 2; # tracks is lazyload
};

{ # nested get
    my $session = $mapper->begin_session;
    my $a = $session->get( 'MyTest11::Artist' => 1 );
    is $a->name, 'Led Zeppelin';
    is $a->id, 1;

    is ref($a->cds), 'ARRAY';
    my $cd_id = 1;
    for my $cd ( @{$a->cds} ) {
        is $cd->id, $cd_id++;
    }
    is $cd_id, 11;

    my $cd2 = $a->cds->[1];
    is $cd2->id, 2;
    is $cd2->title, 'Led Zeppelin II';
    is ref($cd2->tracks), 'ARRAY';
    my $track_no = 1;
    for my $track ( @{$cd2->tracks} ) {
        is $track->track_no, $track_no++;
    }
    is $track_no, 10;

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
