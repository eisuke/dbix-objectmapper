use strict;
use warnings;
use Test::More;

use DBIx::ObjectMapper;
use DBIx::ObjectMapper::Engine::DBI;

BEGIN {
    eval "require Moose";
    plan skip_all => 'Moose required this test' if $@;
};

{
    package Player;
    use Moose;

    has 'id' => (
        is => 'rw',
        isa => 'Int',
    );

    has 'name' => (
        is => 'rw',
        isa => 'Str',
    );

    __PACKAGE__->meta->make_immutable;
};
{
    package Footballer;
    use Moose;

    extends 'Player';

    has 'club' => (
        is => 'rw',
        isa => 'Str',
    );

    __PACKAGE__->meta->make_immutable;
};

{
    package Cricketer;
    use Moose;

    extends 'Player';

    has 'batting_average' => (
        is => 'rw',
        isa => 'Int',
    );

    __PACKAGE__->meta->make_immutable;
};

{
    package Bowler;
    use Moose;

    extends 'Cricketer';

    has 'bowling_average' => (
        is => 'rw',
        isa => 'Int',
    );

    __PACKAGE__->meta->make_immutable;
};

my $engine = DBIx::ObjectMapper::Engine::DBI->new({
    dsn => 'DBI:SQLite:',
    on_connect_do => [
        q{CREATE TABLE players ( id INTEGER PRIMARY KEY, name TEXT, type VARCHAR(16))},
        q{CREATE TABLE footballers ( id INT PRIMARY KEY REFERENCES players(id), club TEXT)},
        q{CREATE TABLE cricketers ( id INT PRIMARY KEY REFERENCES players(id), batting_average INT )},
        q{CREATE TABLE bowlers ( id INT PRIMARY KEY REFERENCES players(id), bowling_average INT )},
    ]
});

# mapperを作成
my $mapper = DBIx::ObjectMapper->new( engine => $engine );
$mapper->metadata->autoload_all_tables;

$mapper->maps(
    $mapper->metadata->table('players') => 'Player',
    polymorphic_on => 'type',
    attributes => {
        include => [qw(id name)]
    }
);

$mapper->maps(
    $mapper->metadata->table('footballers') => 'Footballer',
    inherits => 'Player',
    polymorphic_identity => 'footballer',
    attributes => {
        include => [qw(id name club)]
    }
);

$mapper->maps(
    $mapper->metadata->table('cricketers') => 'Cricketer',
    inherits => 'Player',
    polymorphic_identity => 'cricketer',
    attributes => {
        include => [qw(id name batting_average)]
    }
);

$mapper->maps(
    $mapper->metadata->table('bowlers') => 'Bowler',
    inherits => 'Cricketer',
    polymorphic_identity => 'bowler',
    attributes => {
        include => [qw(id name batting_average bowling_average)]
    }
);

my $session = $mapper->begin_session;

my $footballer = Footballer->new(
    name => 'Franz Anton Beckenbauer',
    club => 'Bayern München',
);

$session->add($footballer);
$session->commit;
# INSERT INTO player ( id, name, type ) VALUES( 1, 'Franz Anton Beckenbauer', 'footballer' );
# INSERT INTO fooballers ( id, club ) VALUES( 1, 'Bayern München');

my $cricketer = Cricketer->new(
    name => 'Hoge',
    batting_average => 10,
);
$session->add($cricketer);
$session->commit;
# INSERT INTO player ( id, name, type ) VALUES( 2, 'Hoge', 'cricketer' );
# INSERT INTO cricketers ( id, batting_average ) VALUES( 2, 10 )

my $bowler = Bowler->new(
    name => 'Fuga',
    bowling_average => 20,
    batting_average => 10,
);

$session->add($bowler);
$session->commit;
# INSERT INTO player ( id, name, type ) VALUES( 3, 'Fuga', 'bowler' );
# INSERT INTO bowlers ( id, bowling_average ) VALUES( 3, 20 );

my $it = $session->search('Player')->execute;
# SELECT id,name FROM players;
my $cnt = 0;
while( my $p = $it->next ) {
    ok $p;
    $cnt++;
}
is $cnt, 3;

my $it2 = $session->search('Footballer')->execute;
# SELECT player.id,player.name,fooballer.club FROM players LEFT JOIN footballer ON footballer.id = player.id WHERE type = 'footballer';
my $cnt2 = 0;
while( my $f = $it2->next ){
    ok $f;
    is ref($f), 'Footballer';
    $cnt2++;
}

is $cnt2, 1;

my $it3 = $session->search('Player')->with_polymorphic('*')->execute;
# SELECT player.id,player.name,footballer.club,cricketer.batting_average, bowler.bowling_average FROM pleyers LEFT JOIN footballer ON footballer.id = player.id LEFT JOIN cricketers ON cricketers.id = player.id
my %ref_cnt;
while( my $p2 = $it3->next ) {
    ok $p2;
    $ref_cnt{ref($p2)}++;
}

is $ref_cnt{Footballer}, 1;
is $ref_cnt{Cricketer}, 1;
is $ref_cnt{Bowler}, 1;

done_testing;
