package Data::ObjectMapper::Log;
use strict;
use warnings;
use Try::Tiny;

try {
    require Log::Any::Adapter;
    Log::Any::Adapter->import;
    my $min_level = 'notice';
    $min_level = 'debug' if $ENV{MAPPER_DEBUG};

    Log::Any::Adapter->set(
        { category => qr/^Data::ObjectMapper/ },
        'Dispatch',
        outputs => [
            [
                'Screen',
                min_level => $min_level,
                newline => 1,
            ]
        ],
        callbacks => sub {
            my %param = @_;
            return sprintf("[%s] %s", $param{level}, $param{message});
        }
    );
};

1;
