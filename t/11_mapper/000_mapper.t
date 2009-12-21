use strict;
use warnings;
use Test::More;
use Test::Exception;

use Data::ObjectMapper::Metadata;
use Data::ObjectMapper::Engine::DBI;
use Data::ObjectMapper::Mapper;

use Scalar::Util;
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

sub is_same_addr($$) {
    is Scalar::Util::refaddr($_[0]), Scalar::Util::refaddr($_[1]);
}

{ # map defined class
    my $mapped_class = 'MyTest::Basic::Artist';
    ok my $mapper = Data::ObjectMapper::Mapper->new(
        $artist_table => $mapped_class
    );

    my $mapped_object = $mapper->is_mapped($mapped_class);
    is_same_addr $mapper,$mapped_object;

    ok $mapped_class->can('__mapper__');
    is_same_addr $mapper, $mapped_class->__mapper__;

    for my $c ( @{$artist_table->columns} ) {
        is_deeply $mapper->attributes_config->{$c->name}{isa}, $c;
    }
};

{ # map auto generate class
    my $mapped_class = 'MyTest::Basic::ArtistAuto';
    ok my $mapper = Data::ObjectMapper::Mapper->new(
        $meta->t('artist') => $mapped_class,
        accessors   => +{ auto => 1 },
        constructor => +{ auto => 1 },
    );

    is_same_addr $mapper, Data::ObjectMapper::Mapper->is_mapped($mapped_class);
    ok $mapped_class->can('firstname');
    ok $mapped_class->can('lastname');
    ok $mapped_class->can('id');

    ok my $obj = $mapped_class->new(
        { id => 1, firstname => 'f', lastname => 'l' } );
    is $obj->firstname, 'f';
    is $obj->lastname, 'l';
    is $obj->id, 1;
};

{ # attribute prefix
    my $mapped_class = 'MyTest::Basic::ArtistAutoPrefix';
    ok my $mapper = Data::ObjectMapper::Mapper->new(
        $meta->t('artist') => $mapped_class,
        accessors   => +{ auto => 1 },
        constructor => +{ auto => 1 },
        attributes  => +{ prefix => '_' },
    );

    is_same_addr $mapper, Data::ObjectMapper::Mapper->is_mapped($mapped_class);
    ok $mapped_class->can('_firstname');
    ok $mapped_class->can('_lastname');
    ok $mapped_class->can('_id');
    ok !$mapped_class->can('firstname');
    ok !$mapped_class->can('lastname');
    ok !$mapped_class->can('id');

    ok my $obj = $mapped_class->new(
        { _id => 1, _firstname => 'f', _lastname => 'l' } );
    is $obj->_firstname, 'f';
    is $obj->_lastname, 'l';
    is $obj->_id, 1;

    dies_ok {
        $mapped_class->new({ id => 1, firstname => 'f', lastname => 'l' } );
    };

};

{ # attribute include option
    my $mapped_class = 'MyTest::Basic::ArtistAutoInclude';
    ok my $mapper = Data::ObjectMapper::Mapper->new(
        $meta->t('artist') => $mapped_class,
        accessors   => +{ auto => 1 },
        constructor => +{ auto => 1 },
        attributes  => +{
            include => +[qw(id lastname)],
        }
    );

    ok $mapped_class->can('id');
    ok $mapped_class->can('lastname');
    ok !$mapped_class->can('firstname');

    ok my $obj = $mapped_class->new({ id => 1, lastname => 'l' } );
    is $obj->lastname, 'l';
    is $obj->id, 1;

    dies_ok {
        $mapped_class->new({ id => 1, firstname => 'f', lastname => 'l' } );
    };
};

{ # attribute exclue option
    my $mapped_class = 'MyTest::Basic::ArtistAutoExclude';
    ok my $mapper = Data::ObjectMapper::Mapper->new(
        $meta->t('artist') => $mapped_class,
        accessors   => +{ auto => 1 },
        constructor => +{ auto => 1 },
        attributes  => +{
            exclude => +[qw(lastname)],
        }
    );

    ok $mapped_class->can('firstname');
    ok $mapped_class->can('id');
    ok !$mapped_class->can('lastname');

    ok my $obj = $mapped_class->new(
        { id => 1, firstname => 'f' } );
    is $obj->firstname, 'f';
    is $obj->id, 1;

    dies_ok {
        $mapped_class->new({ id => 1, firstname => 'f', lastname => 'l' } );
    };
};

{ # attribute include and exclude  option
    my $mapped_class = 'MyTest::Basic::ArtistAutoIncludeExclude';
    ok my $mapper = Data::ObjectMapper::Mapper->new(
        $meta->t('artist') => $mapped_class,
        accessors   => +{ auto => 1 },
        constructor => +{ auto => 1 },
        attributes  => +{
            include => +[qw(firstname lastname)],
            exclude => +[qw(lastname)],
        }
    );

    ok $mapped_class->can('firstname');
    ok !$mapped_class->can('id');
    ok !$mapped_class->can('lastname');

    ok my $obj = $mapped_class->new( { firstname => 'f' } );
    is $obj->firstname, 'f';

    dies_ok {
        $mapped_class->new({ id => 1, firstname => 'f', lastname => 'l' } );
    };
};


{ # map not exsits class
    my $mapped_class = 'MyTest::Basic::ArtistAutoNotExists';
    dies_ok {
        my $mapper = Data::ObjectMapper::Mapper->new(
            $meta->t('artist') => $mapped_class,
        );
    };
};

{ # accessor only XXX
1;
};

{ # constructor only XXXX
1;
};



=pod

    my $mapped_artist = Data::ObjectMapper::Mapper->new(
        $meta->t('artist') => 'My::Artist',
        attributes => {
            include    => [],
            exclude    => [],
            prefix     => '',
            properties => +{
                isa               => undef,
                lazy              => 0,
                validation        => 0,
                validation_method => undef,
            }
        },
        accessors => +{
            auto       => 0,
            exclude    => [],
            do_replace => 0,
        },
        constructor => +{
            name     => 'new',
            arg_type => 'HASHREF',
            auto     => 0,
        },
        default_condition => [

        ],
    );

=cut




done_testing;

__END__

    my $session = Data::ObjectMapper->init_session;
    my $artist = $session->query('MyTest::Basic::Artist')->find(1);

    is $artist->firstname, 'a1';
    is $artist->lastname, 'b1';
    is $artist->fullname, 'a1 b1';

    $artist->firstname('a1-2');
    $artist->lastname('b1-2');
    is $artist->fullname, 'a1-2 b1-2';

    $session->save($artist);

    require Data::Dumper;
    print Data::Dumper::Dumper($artist);

__END__


