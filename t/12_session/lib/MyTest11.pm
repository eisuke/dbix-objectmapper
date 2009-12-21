package MyTest11;
use strict;
use warnings;

use Data::ObjectMapper::Engine::DBI;
use Data::ObjectMapper::Metadata;
use Data::ObjectMapper::Mapper;

my $engine = Data::ObjectMapper::Engine::DBI->new({
    dsn => 'DBI:SQLite:',
    username => '',
    password => '',
    on_connect_do => [
        q{CREATE TABLE artist( id integer primary key, name text )},
        q{CREATE TABLE cd( id integer primary key, title text, artist integer)},
        q{CREATE TABLE track( id integer primary key, cd integer not null, track_no int, title text)},
    ],
});

my $meta = Data::ObjectMapper::Metadata->new( engine => $engine );

my $artist = $meta->table( artist => { autoload_column => 1 } );
my $cd = $meta->table( cd => { autoload_column => 1 } );
my $track = $meta->table( track => { autoload_column => 1 } );

my $artist_mapper = Data::ObjectMapper::Mapper->new(
    $artist => 'MyTest11::Artist',
    constructor => { auto => 1 },
    accessors => { auto => 1 },
);

my $cd_mapper = Data::ObjectMapper::Mapper->new(
    $cd => 'MyTest11::Cd',
    constructor => { auto => 1 },
    accessors => { auto => 1 },
);

my $track_mapper = Data::ObjectMapper::Mapper->new(
    $artist => 'MyTest11::Track',
    constructor => { auto => 1 },
    accessors => { auto => 1 },
);

sub meta { $meta }

sub engine { $engine }

sub setup_default_data {
    my $self = shift;
    my $artist_ins = $artist->insert->values( name => 'Led Zeppelin' )->execute(['id']);
    my $artist_id = $artist_ins->{id};

    my $cds = [
        {
        'Led Zeppelin' => [
            'GOOD TIMES BAD TIMES',
            'BABE I\'M GONNA LEAVE YOU',
            'YOU SHOOK ME',
            'DAZED AND CONFUSED',
            'YOUR TIME IS GONNA COME',
            'BLACK MOUNTAIN SIDE',
            'COMMUNICATION BREAKDOWN',
            'I CAN\'T QUIT YOU BABY',
            'HOW MANY MORE TIMES'
        ],
        },{
        'Led Zeppelin II' => [
            'WHOLE LOTTA LOVE',
            'WHAT IS AND WHAT SHOULD NEVER BE',
            'LEMON SONG,THE',
            'THANK YOU',
            'HEARTBREAKER',
            'LIVING LOVING MAID(SHE\'S JUST A WOMAN)',
            'RAMBLE ON',
            'MOBY DICK',
            'BRING IT ON HOME'
        ],
        },{
        'Led Zeppelin III' => [
            'IMMIGRANT SONG',
            'FRIENDS',
            'CELEBRATION DAY',
            'SINCE I\'VE BEEN LOVING YOU',
            'OUT ON THE TILES',
            'GALLOWS POLE',
            'TANGERINE',
            'THAT\'S THE WAY',
            'BRON-Y-AUR STOMP',
            'HATS OFF TO (ROY) HARPER'
        ],
        },{
        'Led Zeppelin IV' => [
            'BLACK DOG',
            'ROCK AND ROLL',
            'BATTLE OF EVERMORE,THE',
            'STAIRWAY TO HEAVEN',
            'MISTY MOUNTAIN HOP',
            'FOUR STICKS',
            'GOING TO CALIFORNIA',
            'WHEN THE LEVEE BREAKS'
        ],
        },{
        'Houses Of The Holy' => [
            'SONG REMAINS THE SAME,THE',
            'RAIN SONG,THE',
            'OVER THE HILLS AND FAR AWAY',
            'CRUNGE,THE',
            'DANCING DAYS',
            'D\'YER MAK\'ER',
            'NO QUARTER',
            'OCEAN,THE'
        ],
        },{
        'Physical Graffiti' => [
            'CUSTARD PIE',
            'ROVER,THE',
            'IN MY TIME OF DYING',
            'HOUSES OF THE HOLY',
            'TRAMPLED UNDER FOOT',
            'KASHMIR',
            'IN THE LIGHT',
            'BRON-YR-AUR',
            'DOWN BY THE SEASIDE',
            'THEN YEARS GONE',
            'NIGHT FLIGHT',
            'WANTON SONG,THE',
            'BOOGIE WITH STU',
            'BLACK COUNTRY WOMAN',
            'SICK AGAIN'
        ],
        },{
        'Presence' => [
            'ACHILLES LAST STAND',
            'FOR YOUR LIFE',
            'ROYAL ORLEANS',
            'NOBODY\'S FAULT BUT MINE',
            'CANDY STORE ROCK',
            'HOTS ON FOR NOWHERE',
            'TEA FOR ONE'
        ],
        },{
        'The Song Remains The Same' => [
            'ROCK AND ROLL',
            'CELEBRATION DAY',
            'BLACK DOG(INCLUDING BRING IT ON HOME)',
            'OVER THE HILLS AND FAR AWAY',
            'MISTY MOUNTAIN HOP',
            'SINCE I\'VE BEEN LOVING YOU',
            'NO QUARTER',
            'SONG REMAINS THE SAME,THE',
            'RAIN SONG',
            'OCEAN,THE',
            'DAZED AND CONFUSED',
            'STAIRWAY TO HEAVEN',
            'MOBY DICK',
            'HEARTBREAKER',
            'WHOLE LOTTA LOVE'
        ],
        },{
        'In Through The Out Door' => [
            'IN THE EVENING',
            'SOUTH BOUND SAUREZ',
            'FOOL IN THE RAIN',
            'HOT DOG',
            'CAROUSELAMBRA',
            'ALL MY LOVE',
            'I\'M GONNA CRAWL'
        ],
        },{
        'Coda' => [
            'WE\'RE GONNA GROOVE',
            'POOR TOM',
            'I CAN\'T QUIT YOU BABY',
            'WALTER\'S WALK',
            'OZONE BABY',
            'DARLENE',
            'BONZO\'S MONTREUX',
            'WEARING AND TEARING',
            'BABY COME ON HOME',
            'TRAVELLING RIVERSIDE BLUES',
            'WHITE SUMMER/BLACK MOUNTAIN SIDE',
            'HEY HEY WHAT CAN I DO'
        ]
        }
    ];

    for ( @$cds ) {
        my ($title, $tracks) = each %$_;

        my $cd_ins = $cd->insert->values(
            title => $title,
            artist => $artist_id
        )->execute(['id']);

        my $cd_id = $cd_ins->{id};

        my $no = 1;
        for (@$tracks) {
            $track->insert->values(
                cd       => $cd_id,
                track_no => $no++,
                title    => $_,
            )->execute;
        }
    }

};



1;

