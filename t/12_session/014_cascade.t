use strict;
use warnings;
use Test::More;
use File::Spec;
use FindBin;
use lib File::Spec->catfile($FindBin::Bin, 'lib');
use MyTest11;


MyTest11->setup_default_data;
MyTest11->mapping_with_foreign_key;

my $mapper = MyTest11->mapper;

{
    my $session = $mapper->begin_session;

    my $cd     = $mapper->metadata->t('cd');
    my $track  = $mapper->metadata->t('track');
    my $cd1 = $session->get( 'MyTest11::Cd' => 1 );
    $session->delete($cd1);
    $session->flush;

    # check
    ok !$session->get( 'MyTest11::Cd' => 1 );
    my $cd1_tracks
        = $session->query('MyTest11::Track')->where( $track->c('cd_id') == 1 )
        ->execute;
    is scalar(@$cd1_tracks), 0;
};


done_testing;
