use strict;
use warnings;
use Test::More;
use MIME::Base64;
use DateTime;
use DateTime::Duration;
use Bit::Vector;
use Data::ObjectMapper::Engine::DBI;
use Data::ObjectMapper;

my ($dsn, $user, $pass) = @ENV{map { "MAPPER_TEST_PG_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{MAPPER_TEST_PG_DSN}, _USER and _PASS to run this test' unless ($dsn && $user);


my $engine = Data::ObjectMapper::Engine::DBI->new({
    dsn => $dsn,
    username => $user,
    password => $pass,
    on_connect_do => [
        q{
CREATE TEMP TABLE test_types (
  id SERIAL PRIMARY KEY,
  array_int integer[],
  array_2d_text text[][],
  bit BIT(2),
  created TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT NOW(),
  modified TIMESTAMP,
  photo bytea,
  d DATE,
  t TIME,
  intvl INTERVAL
)
},
    ]
});

my $mapper = Data::ObjectMapper->new( engine => $engine );
my $table = $mapper->metadata->table( test_types => 'autoload' );
my $GIF = 'R0lGODlhAQABAJEAAAAAAP///////wAAACH5BAUUAAIALAAAAAABAAEAAAICVAEAOw==
';
my $now = DateTime->now;
my $duration = DateTime::Duration->new(
    years   => 3,
    months  => 5,
    weeks   => 1,
    days    => 1,
    hours   => 6,
    minutes => 15,
    seconds => 45,
    nanoseconds => 12000
);

$table->insert(
    array_int => [ 1, 2, 3, 4 ],
    array_2d_text => [ [qw(a b c c)], [qw(e f g h)] ],
    bit => '11',
    photo => MIME::Base64::decode($GIF),
    d     => $now,
    t     => $now,
    intvl => $duration,
)->execute;


{ # find
    ok my $d = $table->find(1);
    is_deeply $d->{array_int}, [ 1, 2, 3, 4 ];
    is_deeply $d->{array_2d_text}, [ [qw(a b c c)], [qw(e f g h)] ];
    is $d->{bit}->to_Hex, 3;
    is MIME::Base64::encode($d->{photo}), $GIF;
    is ref($d->{created}), 'DateTime';
    ok !$d->{modified};
    is $d->{d}->ymd('-'), $now->ymd('-');
    is $d->{t}->hms(':'), $now->hms(':');
    is $d->{intvl}->years, 3;
    is $d->{intvl}->months, 5;
    is $d->{intvl}->weeks, 1;
    is $d->{intvl}->days, 1;
    is $d->{intvl}->minutes, 15;
    is $d->{intvl}->seconds, 45;
    is $d->{intvl}->nanoseconds, 12000;
};

{ # search by array
    ok my $d
        = $table->select->where( $table->c('array_int') == \[ 1, 2, 3, 4 ] )
        ->first;
    is $d->{id}, 1;
};

{ # search by array2d
    ok my $d = $table->select->where(
        $table->c('array_2d_text') == \[ [qw(a b c c)], [qw(e f g h)] ],
    )->first;
    is $d->{id}, 1;
};

{ # search by bit
    ok my $d = $table->select->where(
        $table->c('bit') == Bit::Vector->new_Hex(2,3),
    )->first;

    is $d->{id}, 1;
};

{ # search by bytea
    ok my $d = $table->select->where(
        $table->c('photo') == MIME::Base64::decode($GIF),
    )->first;
    is $d->{id}, 1;
};

{ # search by date
    ok my $d = $table->select->where(
        $table->c('d') == $now,
    )->first;
    is $d->{id}, 1;
};

{ # search by time
    ok my $d = $table->select->where(
        $table->c('t') == $now,
    )->first;
    is $d->{id}, 1;
};

{ # search by duration
    ok my $d = $table->select->where(
        $table->c('intvl') > DateTime::Duration->new(
            years => 3
        ),
    )->first;
    is $d->{id}, 1;

};

{ # update
    ok $table->update->set( modified => $now )->where( $table->c('id') == 1 )->execute;
    my $d = $table->find(1);
    is $d->{modified}, $now;
};

done_testing;
