use strict;
use warnings;
use Test::More;
use Test::Exception;
use Data::ObjectMapper::Log;

ok my $log = Data::ObjectMapper::Log->new('warn');

is_deeply ( \%Data::ObjectMapper::Log::LEVEL_TABLE, {
    'info' => 2,
    'trace' => 0,
    'warn' => 4,
    'fatal' => 6,
    'error' => 5,
    'debug' => 1,
    'driver_trace' => 3
});

is $log->level, 4;

for( qw( trace debug info driver_trace warn error fatal ) ) {
    ok $log->can($_);
    ok $log->can('is_' . $_);
}

throws_ok( sub{ $log->exception('exception') }, qr/exception at /, 'exception' );

{
    no warnings 'redefine';
    *Data::ObjectMapper::Log::_log = sub {
        my ( $class, $msg ) = @_;
        ok $msg;
    };
    $log->error('error');
};

done_testing();
