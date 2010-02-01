use strict;
use warnings;
use Test::More;
use Try::Tiny;
use DBIx::ObjectMapper;
use DBIx::ObjectMapper::Engine::DBI;

my $engine = DBIx::ObjectMapper::Engine::DBI->new({
    dsn => 'DBI:SQLite:',
    username => '',
    password => '',
    on_connect_do => [
        q{CREATE TABLE books( id integer primary key, title text)},
    ],
});

my $mapper = DBIx::ObjectMapper->new(
    engine => $engine,
);

my $book = $mapper->metadata->table( 'books' => 'autoload' );

$mapper->maps(
    $book => 'MyTest18::Books',
    accessors => { auto => 1 },
    constructor => { auto => 1 },
);

{
    my $session = $mapper->begin_session();
    is $session->autocommit, 1;
    is $session->autoflush, 0;
    try {
        $session->txn(
            sub{
                is $session->autoflush, 1;
                $session->add( MyTest18::Books->new( title => 'title' . $_ ) )
                    for 1 .. 5;
                die;
                $session->add( MyTest18::Books->new( title => 'title' . $_ ) )
                    for 6 .. 10;
            }
        );
    };
    is $session->autoflush, 0;
};

{
    my $session = $mapper->begin_session;
    is $session->query('MyTest18::Books')->count, 0;
};

{
    my $session = $mapper->begin_session( autocommit => 0 );
    $session->add( MyTest18::Books->new( title => 'title' . $_ ) ) for 1 .. 10;
    $session->commit;

    ok my $b1 = $session->get('MyTest18::Books' => 1);
    $b1->title('title1-update');
    $session->commit;
};

{
    $book->delete->execute;
    my $session = $mapper->begin_session( autocommit => 0 );
    is $session->autoflush, 0;

    try {
        $session->txn(
            sub{
                is $session->autoflush, 1;
                $session->add( MyTest18::Books->new( title => 'title' . $_ ) )
                    for 1 .. 5;
                $session->add( MyTest18::Books->new( title => 'title' . $_ ) )
                    for 6 .. 10;
            }
        );
    };

    is $session->autoflush, 0;
    $session->commit;
};

{
    my $session = $mapper->begin_session;
    is $session->query('MyTest18::Books')->count, 10;
};

{
    $book->delete->execute;
    my $session = $mapper->begin_session( autocommit => 0 );
    is $session->autoflush, 0;

    try {
        $session->txn(
            sub{
                is $session->autoflush, 1;
                $session->add( MyTest18::Books->new( title => 'title' . $_ ) )
                    for 1 .. 5;
                die 'died';
                $session->add( MyTest18::Books->new( title => 'title' . $_ ) )
                    for 6 .. 10;
                $session->commit;
            }
        );
    };

    is $session->autoflush, 0;
    is $session->query('MyTest18::Books')->count, 0;

    $session->add( MyTest18::Books->new( title => 'title' . $_ ) ) for 6 .. 10;
    $session->commit;
};

{
    my $session = $mapper->begin_session;
    is $session->query('MyTest18::Books')->count, 5;
};

done_testing;
