use strict;
use warnings;
use Test::More;

use DBIx::ObjectMapper;
use DBIx::ObjectMapper::Engine::DBI;
use DBIx::ObjectMapper::Metadata::Declare qw(:all);

my $mapper = DBIx::ObjectMapper->new(
    engine => DBIx::ObjectMapper::Engine::DBI->new({
        dsn => 'DBI:SQLite:',
        username => '',
        password => '',
        on_connect_do => [
            q{CREATE TABLE players( id integer primary key, name text, play text )}
        ],
    }),
);

my $players = $mapper->metadata->t(
    'players' => [
        Col( id => Int(), PrimaryKey ),
        Col( name => Text() ),
        Col( play => Text() ),
    ]
);

{
    package My::Player;

    sub new {
        my $class = shift;
        my $attr = shift;
        bless $attr, $class;
    }

    sub id {
        my $self = shift;
        $self->{id} = shift if @_;
        return $self->{id};
    }

    sub name {
        my $self = shift;
        $self->{name} = shift if @_;
        $self->{name};
    }

    sub play {
        my $self = shift;
        $self->{play} = shift if @_;
        return $self->{play};
    }

    1;
};

{
    package My::Footballer;
    use base qw(My::Player);

    1;
};

{
    package My::TennisPlayer;
    use base qw(My::Player);

    1;
};

$mapper->maps( $players => 'My::Player' );
$mapper->maps(
    $players => 'My::Footballer',
    default_condition => [ $players->c('play') == 'football' ],
    default_value => { play => 'football' },
);
$mapper->maps(
    $players => 'My::TennisPlayer',
    default_condition => [ $players->c('play') == 'tennis' ],
    default_value => { play => 'tennis' },
);

{
    my $session = $mapper->begin_session;
    ok $session->add_all(
        My::Footballer->new({
            name => 'Franz Anton Beckenbauer',
        }),
        My::Footballer->new({
            name => 'Johan Cruijff',
        }),
        My::TennisPlayer->new({
            name => 'John McEnroe',
        }),
    );
};

{
    my $session = $mapper->begin_session;
    my $it = $session->query('My::Player')->execute;
    is @$it, 3;

    my $footballer = $session->query('My::Footballer')->execute;
    is @$footballer, 2;

    my $tennis_player = $session->query('My::TennisPlayer')->execute;
    is @$tennis_player, 1;
};

{
    my $session = $mapper->begin_session;
    ok my $beckenbauer = $session->get( 'My::Footballer' => 1 );
    is $beckenbauer->name, 'Franz Anton Beckenbauer';
    $beckenbauer->id(10);
    $session->flush;

    ok $session->get( 'My::Footballer' => 10 );
    ok !$session->get( 'My::TennisPlayer' => 10 );
};

done_testing;
