use strict;
use warnings;
use Test::More;
use Test::Exception;

use Scalar::Util qw(blessed);
use Data::ObjectMapper::Engine::DBI;
BEGIN { use_ok('Data::ObjectMapper::Query') }

my $engine = Data::ObjectMapper::Engine::DBI->new({
    dsn => 'DBI:SQLite:',
    username => '',
    password => '',
    on_connect_do => [
        q{CREATE TABLE artist (id integer primary key, name text)},
        q{INSERT INTO artist (name) VALUES('artist1')},
        q{INSERT INTO artist (name) VALUES('artist2')},
        q{INSERT INTO artist (name) VALUES('artist3')},
        q{INSERT INTO artist (name) VALUES('artist4')},
        q{INSERT INTO artist (name) VALUES('artist5')},
    ],
});

my $query = Data::ObjectMapper::Query->new($engine);
ok blessed($query->select);
is ref($query->select), 'Data::ObjectMapper::Query::Select';
ok blessed($query->update);
is ref($query->update), 'Data::ObjectMapper::Query::Update';
ok blessed($query->delete);
is ref($query->delete), 'Data::ObjectMapper::Query::Delete';
ok blessed($query->insert);
is ref($query->insert), 'Data::ObjectMapper::Query::Insert';

{ # select
    my @artists = @{$query->select->from('artist')->order_by('id')->execute};
    for my $i ( 0 .. $#artists ) {
        is $artists[$i]->[0], $i+1;
        is $artists[$i]->[1], 'artist' . ($i+1);
    }
};

{ # insert
    ok my $a1
        = $query->insert->table('artist')->values( name => 'add1' )->execute;
    ok my $a2
        = $query->insert->table('artist')->values( name => 'add2' )->execute;
    dies_ok {
        $query->insert->table('artist')->values( hoge => 'hoge' )->execute;
    };
};

{ # update
    ok $query->update->table('artist')->where( [ id => 1 ] )
        ->set( name => 'artist1-1' )->execute;

    my $it = $query->select->from('artist')->where( [ id => 1 ] )->limit(1)
        ->execute;
    my $result = $it->next;
    is $result->[1], 'artist1-1';
};

{ # delete
    $query->delete->table('artist')->where( [ id => 1 ])->execute;
    my $it = $query->select->from('artist')->where( [ id => 1 ] )->limit(1)
        ->execute;
    is $it->size, 0;
    ok !$it->next;
};

{ # select with callback
    my $it = $query->select->from('artist')->order_by('id')->execute(
        sub { { id => $_[0]->[0], name => $_[0]->[1] } }
    );

    while( my $ref = $it->next ) {
        ok $ref->{name};
        ok $ref->{id};
    }

};


done_testing();
