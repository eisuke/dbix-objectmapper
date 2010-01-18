use strict;
use warnings;
use Test::More;
use Test::Exception;
use File::Spec;
use FindBin;
use lib File::Spec->catfile($FindBin::Bin, 'lib');
use MyTest11;

MyTest11->setup_default_data;
MyTest11->mapping_with_foreign_key;

my $mapper = MyTest11->mapper;

{ # has_many/has_one
    my $session = $mapper->begin_session;
    my $artist = $mapper->metadata->t('artist');
    my $cd     = $mapper->metadata->t('cd');
    my $it = $session->query('MyTest11::Artist')->join({ 'cds' => 'linernote' })
        ->where( $cd->c('title')->like('Led Zeppelin%') )->order_by($cd->c('id'))->execute;
    ok $it;

    my $loop_cnt = 0;
    while( my $a = $it->next ) {
        $loop_cnt++;
        is $a->id, 1;
        is $a->name, 'Led Zeppelin';
        is ref($a->cds), 'ARRAY';
        for my $cd ( @{$a->cds} ) {
            ok $cd->id;
            ok $cd->linernote;
            ok $cd->linernote->id;
        }
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

{ # has_many is one record
    my $session = $mapper->begin_session;
    my $artist = $mapper->metadata->t('artist');
    my $cd     = $mapper->metadata->t('cd');

    my $it = $session->query(
        'MyTest11::Artist',
     )
     ->eager_join('cds')
     ->where( $cd->c('id') == 1 )
     ->execute;

    my $loop_cnt = 0;
    while( my $artist = $it->next ) {
        is ref($artist->cds), 'ARRAY';
        is scalar(@{$artist->cds}), 1;
        $loop_cnt++;
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
        # そこまで必要であれば、metadata.queryを利用したほうがいいと思う
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

{ # get with eargerload
    my $session = $mapper->begin_session;
    my $cd = $session->get( 'MyTest11::Cd' => 1, { eagerload => 'artist' } );
    is $cd->artist->name, 'Led Zeppelin';
    is $cd->artist->id, 1;
    is $session->uow->query_cnt, 1;
};

{ # get with eargerload2
    my $session = $mapper->begin_session;
    my $cd = $session->get(
        'MyTest11::Cd' => 1,
        { eagerload => ['artist', 'linernote'] }
    );
    is $cd->artist->name, 'Led Zeppelin';
    is $cd->artist->id, 1;
    ok $cd->linernote;
    ok $cd->linernote->id;
    is $session->uow->query_cnt, 1;
};

{ # egear and join
    my $session = $mapper->begin_session;
    my $track = $mapper->metadata->t('track');
    my $it = $session->query('MyTest11::Cd')->eager_join('linernote')
        ->add_join('tracks')
        ->where( $track->c('track_no') > 9 )->execute;
    my $loop_cnt = 0;
    while( my $cd = $it->next ) {
        ok $cd->id;
        ok $cd->linernote;
        ok $cd->linernote->id;
        ok $cd->tracks;
        is ref($cd->tracks), 'ARRAY';
        $loop_cnt++;
    }
    is $session->uow->query_cnt, 1 + $loop_cnt; # tracks is lazyload
};

{ # egear and join2
    my $session = $mapper->begin_session;
    my $liner = $mapper->metadata->t('linernote');

    my $it = $session->query('MyTest11::Cd')->eager_join('tracks')
        ->add_join('linernote')
        ->where( $liner->c('note')->func('length') > 0 )->execute;
    my $loop_cnt = 0;
    while( my $cd = $it->next ) {
        ok $cd->id;
        ok $cd->linernote;
        ok $cd->linernote->id;
        ok $cd->tracks;
        is ref($cd->tracks), 'ARRAY';
        $loop_cnt++;
    }

    is $session->uow->query_cnt, 1 + $loop_cnt; # tracks is lazyload
};


{ # errors
    my $session = $mapper->begin_session;

    throws_ok { # joined same table
        $session->query('MyTest11::Cd')
            ->eager_join('linernote')
            ->add_join('linernote')
            ->execute;
    } qr/has already been defined./;

    throws_ok { # not exists
        $session->query('MyTest11::Artist')
            ->eager_join('linernote')
            ->execute;
    } qr/linernote does not exists/;


    dies_ok {
        $session->query('MyTest11::Artist')
            ->eager_join({ cds => 'linernote' })
            ->add_join('linernote')
            ->execute;
    };

};

{ # has_many modify
    my $session = $mapper->begin_session;
    my $artist = $session->get( 'MyTest11::Artist' => 1 );
    ok $artist->cds;
    is scalar(@{$artist->cds}), 10;
    my $cd1 = shift(@{$artist->cds});
    is scalar(@{$artist->cds}), 9;
    is $cd1->__mapper__->status, 'persistent';
    # deleted $cd1
};

{ # check
    my $session = $mapper->begin_session;
    my $artist = $session->get( 'MyTest11::Artist' => 1 );
    is scalar(@{$artist->cds}), 9;
};

{ # add
    my $session = $mapper->begin_session;
    my $artist = $session->get( 'MyTest11::Artist' => 1 );
    my $new_cd = MyTest11::Cd->new(
        id => 1,
        artist_id => $artist->id,
        title => 'Led Zeppelin',
    );
    unshift(@{$artist->cds}, $new_cd);
};

{ # check
    my $session = $mapper->begin_session;
    my $artist = $session->get( 'MyTest11::Artist' => 1 );
    is scalar(@{$artist->cds}), 10;
};

done_testing;

__END__
