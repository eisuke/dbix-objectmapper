use strict;
use warnings;
use Test::More;
use Test::Exception;

use DBIx::ObjectMapper::Engine::DBI;
use DBIx::ObjectMapper;
use DBIx::ObjectMapper::Metadata::Query;

my $engine = DBIx::ObjectMapper::Engine::DBI->new({
    dsn => 'DBI:SQLite:',
    username => '',
    password => '',
    on_connect_do => [
        q{CREATE TABLE customer (id integer primary key, name text)},
        q{CREATE TABLE email ( customer_id integer primary key, email text)},
    ],
});

my $mapper = DBIx::ObjectMapper->new( engine => $engine );
my $meta = $mapper->metadata;
$meta->autoload_all_tables;
ok my $customer = $meta->t('customer');
ok my $email = $meta->t('email');

$customer->insert( name => $_ )->execute for qw(cust1 cust2 cust3);
$email->insert( customer_id => 1, email => 'cust1@example.com' )->execute;
$email->insert( customer_id => 2, email => 'cust2@example.com' )->execute;
$email->insert( customer_id => 3, email => 'cust3@example.com' )->execute;

{
    ok my $query = $customer->select->column(@{$customer->columns}, @{$customer->columns})->join([ $email, [ $email->c('customer_id') == $customer->c('id') ] ]);

    dies_ok {
        my $meta_query = DBIx::ObjectMapper::Metadata::Query->new(
            'customer_and_email' => $query,
            { engine => $engine },
        );
    };
}


ok my $query = $customer->select->column(@{$customer->columns}, @{$email->columns} )->join([ $email, [ $email->c('customer_id') == $customer->c('id') ] ]);

ok my $meta_query = DBIx::ObjectMapper::Metadata::Query->new(
    'customer_and_email' => $query,
    { engine => $engine },
);

{
    is $meta_query->table_name, 'customer_and_email';
    is $meta_query, 'customer_and_email';
    is_deeply $meta_query->columns, [
        map { $_->as_alias('customer_and_email') }
            ( @{ $customer->columns }, @{ $email->columns } )
    ];

    is $meta_query->c('id'), 'customer_and_email.id';
    is $meta_query->c('name'), 'customer_and_email.name';
    is $meta_query->c('email'), 'customer_and_email.email';

    ok my $it = $meta_query->select->order_by($meta_query->c('id'))->execute;

    my $loop_cnt = 0;
    while( my $c = $it->next ) {
        $loop_cnt++;
        is $c->{id}, $loop_cnt;
        is $c->{name}, 'cust' . $loop_cnt;
        is $c->{email}, 'cust' . $loop_cnt . '@example.com';
    }
    is $loop_cnt, 3;

    my @res = @$it;
    is $res[0]->{name}, 'cust1';
    is $res[1]->{name}, 'cust2';
    is $res[2]->{name}, 'cust3';

    ok my $clone = $meta_query->clone('customer_and_email2');
    is $clone->table_name, 'customer_and_email2';
};

ok $mapper->maps(
    [ $query => 'customer_email', { primary_key => ['id'] } ] => 'MyTest002::Customer',
    accessors => { auto => 1 },
    constructor => { auto => 1 },
);

{ # session
    my $session = $mapper->begin_session;

    ok my $cust1 = $session->get( 'MyTest002::Customer' => 1 );
    is $cust1->name, 'cust1';
    is $cust1->email, 'cust1@example.com';
    is $cust1->id, 1;

    ok my $it = $session->query('MyTest002::Customer')->where(
        $customer->c('id')->as_alias('customer_email') < 10
    )->execute;

    my $loop_cnt = 0;
    while( my $c = $it->next ) {
        $loop_cnt++;
        is $c->id, $loop_cnt;
        is $c->name, 'cust' . $loop_cnt;
        is $c->email, 'cust' . $loop_cnt . '@example.com';
    }

    is $loop_cnt, 3;
};



done_testing;
