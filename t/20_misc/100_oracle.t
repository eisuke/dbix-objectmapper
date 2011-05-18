use strict;
use warnings;
use Test::More;
use DateTime;
use DateTime::Duration;
use DateTime::Format::Oracle;
use DBIx::ObjectMapper::Engine::DBI;
use DBIx::ObjectMapper;

my ($dsn, $user, $pass, $schema) = @ENV{map { "MAPPER_TEST_ORACLE_${_}" } qw/DSN USER PASS SCHEMA/};
plan skip_all => 'Set $ENV{MAPPER_TEST_ORACLE_DSN}, _USER, _PASS, and _SCHEMA to run this test.' unless ($dsn && $user);

my $engine = DBIx::ObjectMapper::Engine::DBI->new({
    dsn           => $dsn,
    username      => $user,
    password      => $pass,
    db_schema     => $schema,
    on_connect_do => [

        # Ensure date format for DATE fields is consistent before we start inserting rows
        "alter session set nls_date_format = '" .
        DateTime::Format::Oracle->nls_date_format .
        "'",

        # ...and the timestamp format for TIMESTAMP fields
        "alter session set nls_timestamp_format = '" .
        DateTime::Format::Oracle->nls_date_format .
        "'",

        # Create test table
        q{
CREATE TABLE test_types (
  id INTEGER PRIMARY KEY,
  i    INT,
  num  NUMERIC(10,2),
  f    NUMBER(5,4),
  deci DECIMAL(10,2),
  photo BLOB,
  lblob LONG,
  created TIMESTAMP(0) DEFAULT SYSDATE,
  modified TIMESTAMP,
  dt DATE
)

}
    ],
    on_disconnect_do => q{DROP TABLE test_types},
    time_zone => 'Asia/Tokyo',
});

my $mapper = DBIx::ObjectMapper->new( engine => $engine );
$mapper->metadata->autoload_all_tables;
my $table = $mapper->metadata->t( 'TEST_TYPES' );
my $GIF = 'R0lGODlhAQABAJEAAAAAAP///////wAAACH5BAUUAAIALAAAAAABAAEAAAICVAEAOw==
';
my $now = DateTime->now( time_zone => 'UTC' );


is $table->c('ID')->type->type, 'numeric';
is $table->c('I')->type->type, 'numeric';
is $table->c('NUM')->type->type, 'numeric';
is $table->c('F')->type->type, 'numeric';
is $table->c('DECI')->type->type, 'numeric';
is $table->c('PHOTO')->type->type, 'blob';
is $table->c('LBLOB')->type->type, 'binary';
is $table->c('CREATED')->type->type, 'datetime';
is $table->c('MODIFIED')->type->type, 'datetime';
is $table->c('DT')->type->type, 'date';


{
    my $r = $table->insert(
        ID   => 1,
        I    => 2,
        NUM  => 0.202927272,
        F    => 0.202927272,
        DECI => 20,
        PHOTO => $GIF,
        LBLOB => $GIF,
        DT => $now,
    )->execute;

    # check last_insert_id
    is $r->{ID}, 1;
};


{ # find
    ok my $d = $table->find(1);

    is $d->{PHOTO}, $GIF;
    is $d->{LBLOB}, $GIF;

    is ref($d->{CREATED}), 'DateTime';
    is $d->{CREATED}->time_zone->name, 'Asia/Tokyo';
    ok !$d->{CREATED}->time_zone->is_utc;
    is $d->{CREATED}->time_zone->offset_for_datetime($now), 9*60*60;

    ok !$d->{MODIFIEd};
    is $d->{DT}->ymd('-'), $now->ymd('-');

    ok $d->{I} == 2;

    ok $d->{NUM} == 0.20;
    ok $d->{F} == 0.2029;
    ok $d->{DECI} == 20.00;

};

{ # search by date
    ok my $d = $table->select->where(
        $table->c('DT') == $now,
    )->first;
    is $d->{ID}, 1;
};

{ # update
    ok $table->update->set( MODIFIED => $now )->where( $table->c('ID') == 1 )->execute;
    my $d = $table->find(1);
    is $d->{MODIFIED}, $now;
};

{ # limit, offset
    ok my $r = $table->select->limit(1)->offset(0)->execute;
    is $r->first->{ID}, 1;
};

$mapper->maps(
    $table => 'My::MyOracleTest',
    accessors => { auto => 1 },
    constructor => { auto => 1 },
);

{ # transaction rollback
    my $session = $mapper->begin_session( autocommit => 0 );
    $session->add( My::MyOracleTest->new( ID => 4, I => 10 ) );
    $session->rollback;
};

{ # check
    my $session = $mapper->begin_session( autocommit => 0 );
    my $attr = $mapper->attribute('My::MyOracleTest');
    is $session->search('My::MyOracleTest')->filter( $attr->p('I') == 10 )->count, 0;
};

{ # transaction commit
    my $session = $mapper->begin_session( autocommit => 0 );
    $session->add( My::MyOracleTest->new( ID => 5, I => 10 ) );
    $session->commit;
};

{ # check
    my $session = $mapper->begin_session( autocommit => 0 );
    my $attr = $mapper->attribute('My::MyOracleTest');
    is $session->search('My::MyOracleTest')->filter( $attr->p('I') == 10 )->count, 1;
};


{ # savepoint
    my $session = $mapper->begin_session( autocommit => 0 );
    $session->add( My::MyOracleTest->new( ID => 6, I => 11 ) );
    eval {
        $session->txn(
            sub {
                $session->add( My::MyOracleTest->new( ID => 1, I => 11 ) );
                $session->commit;
            }
        );
    };
    ok $@;
    $session->add( My::MyOracleTest->new( ID => 7, I => 11 ) );
    $session->commit;
};

{
    my $session = $mapper->begin_session( autocommit => 0 );
    my $attr = $mapper->attribute('My::MyOracleTest');
    is $session->search('My::MyOracleTest')->filter( $attr->p('I') == 11 )->count, 2;
};

done_testing;
