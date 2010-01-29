use strict;
use warnings;
use Test::More;
use DateTime;

use DBIx::ObjectMapper::Engine::DBI;
use DBIx::ObjectMapper::Metadata;

my $now_func = sub { DateTime->now() };

my $engine = DBIx::ObjectMapper::Engine::DBI->new({
    dsn => 'DBI:SQLite:',
    username => '',
    password => '',
    on_connect_do => [
        q{ CREATE TABLE person (id integer primary key, name text, created timestamp, modified timestamp)},
        q{ CREATE TABLE address( id integer primary key, person integer not null, address text, UNIQUE(person, address) ) }
    ],
});

my $meta = DBIx::ObjectMapper::Metadata->new( engine => $engine );
my $person = $meta->table(
    'person' => 'autoload',
    {
        default   => { created => $now_func },
        on_update => { modified => $now_func }
    },
);

my $address = $meta->table( address => 'autoload' );

{ #insert
    ok $person->insert->values(
        $person->c('name')->is('person1'),
    )->execute;

    ok $person->insert->values(
        $person->c('name')->is('person2'),
    )->execute;
};

{ # select
    my @it = @{$person->select->execute()};
    is $it[0]->{name}, 'person1';
    is $it[1]->{name}, 'person2';
    is $it[0]->{id}, 1;
    is $it[1]->{id}, 2;
};

{ # update
    ok $person->update->set( $person->c('name')->is('person22') )->where( $person->c('id') == 1 )->execute;

    my $it = $person->select->where( $person->c('id') == 1 )->execute;
    my $person1 = $it->next;
    is $person1->{name}, 'person22';
};

{ # count function
    ok $address->insert->values(
        $address->c('person')->is(1),
        $address->c('address')->is('address1'),
    )->execute;

    ok $address->insert->values(
        $address->c('person')->is(1),
        $address->c('address')->is('address2'),
    )->execute;

    ok $address->insert->values(
        $address->c('person')->is(1),
        $address->c('address')->is('address3'),
    )->execute;

    ok $address->insert->values(
        $address->c('person')->is(2),
        $address->c('address')->is('address1'),
    )->execute;

    is $address->count->execute, 4;
};

{ # join
    my $it = $person->select->join(
        [ $address => [ $address->c('person') == $person->c('id') ] ]
    )->add_column(
        @{$address->columns}, [ $address->c('person') => 'person_id']
    )->order_by( $person->c('id'), $address->c('id') )->execute;

    for ( 1 .. 4 ) {
        ok my $r = $it->next;
        is ref($r->{address}), 'HASH';
        is $r->{id}, $r->{address}{person};
        is $r->{id}, $r->{address}{person_id};
    }

    ok !$it->next;
}

{ # count, join
    is $person->count->join(
        [ $address => [ $address->c('person') == $person->c('id') ] ]
    )->execute, 4;
};

{ # group by
    my $it = $address->select->column(
        $address->c('person'), { count => [ $address->c('id') ] }
    )->group_by( $address->c('person') )->order_by( $address->c('person'))
        ->execute;

    my $p1 = $it->next;
    is $p1->{person}, 1;
    is $p1->{count}, 3;

    my $p2 = $it->next;
    is $p2->{person}, 2;
    is $p2->{count}, 1;

    ok !$it->next;
};

{ # column alias
    my $it = $address->select->column( $address->c('id')->as('address_id'),
        $address->c('person') )->order_by($address->c('id'))->execute();
    is_deeply $it->next, { address_id => 1, person => 1 };
    is_deeply $it->next, { address_id => 2, person => 1 };
    is_deeply $it->next, { address_id => 3, person => 1 };
    is_deeply $it->next, { address_id => 4, person => 2 };
};

{ # find
    is_deeply $address->find(1), {
        id => 1,
        person => 1,
        address => 'address1',
    };

    is_deeply $address->find([1]), {
        id => 1,
        person => 1,
        address => 'address1',
    };

    is_deeply $address->find({ id => 1 }), {
        id => 1,
        person => 1,
        address => 'address1',
    };

    is_deeply $address->find([ $address->c('id') == 1 ]), {
        id => 1,
        person => 1,
        address => 'address1',
    };

    is_deeply $address->find({ person => 1, address => 'address1' }), {
        id => 1,
        person => 1,
        address => 'address1',
    };

};


{# delete
    ok $person->delete->where( $person->c('id') == 1 )->execute;
    is $person->count->execute, 1;
    ok $person->delete->where( $person->c('id') == 2 )->execute;
    is $person->count->execute, 0;

    is $address->count->execute, 4;
    ok $address->delete->execute;
    is $address->select->column({count=>'*'})->execute->first->{count}, 0;
    is $address->select->column()->execute->first, undef;
};

done_testing();


