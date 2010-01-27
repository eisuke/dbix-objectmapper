use strict;
use warnings;
use Test::More;

use Data::ObjectMapper;
use Data::ObjectMapper::Engine::DBI;

my $mapper = Data::ObjectMapper->new(
    engine => Data::ObjectMapper::Engine::DBI->new({
        dsn => 'DBI:SQLite:',
        username => '',
        password => '',
        on_connect_do => [
            q{CREATE TABLE artist( id integer primary key, name text )},
        ],
    }),
);

my $artist = $mapper->metadata->table( artist => 'autoload' );
my @names = qw(a b c d e f g);
$artist->insert->values({ name => $_ })->execute for @names;

$mapper->maps(
    $artist => 'MyTest11::Artist',
    constructor => { auto => 1 },
    accessors => { auto => 1 },
);

{ # all
    my $session = $mapper->begin_session;
    my $query
        = $session->query('MyTest11::Artist')->order_by( $artist->c('id') );
    my $it = $query->execute();
    my $count = 0;
    while( my $a = $it->next ) {
        is ref($a), 'MyTest11::Artist';
        is $a->id, ++$count;
        is $a->name, $names[$count - 1];
    }
    is $count, 7;
    is $query->count, 7;
};

{ # where
    my $session = $mapper->begin_session;
    my $artist = $session->query('MyTest11::Artist')
        ->where( $artist->c('name')->like('%a%') )->first;
    is $artist->id, 1;
    is $artist->name, 'a';
};

{ # limit/offset
    my $session = $mapper->begin_session;
    my $it      = $session->query('MyTest11::Artist')
        ->order_by( $artist->c('id')->desc )->limit(2)->offset(2)->execute;

    my $loop_cnt = 0;
    my $id = 5;
    while( my $a = $it->next ) {
        is $a->id, $id--;
        $loop_cnt++;
    }
    is $loop_cnt, 2;
};

{ # pager
    my $session = $mapper->begin_session;
    my $query   = $session->query('MyTest11::Artist')
        ->order_by( $artist->c('id') )->limit(2);
    my $pager = $query->pager(1);
    is ref($pager), 'Data::Page';
    is $pager->current_page, 1;
    is $pager->total_entries, 7;

    my $it = $query->execute;
    my $loop_cnt = 0;
    while( my $a = $it->next ) {
        is $a->id, ++$loop_cnt;
    }
    is $loop_cnt, 2;
};

{ # first/count
    my $session = $mapper->begin_session;
    my $query   = $session->query('MyTest11::Artist')
        ->order_by( $artist->c('id') );
    my $a = $query->first;
    is $a->id, 1;
    is $query->count, 7;
};

done_testing;
__END__
