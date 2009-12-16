package Data::ObjectMapper::Engine;
use strict;
use warnings;
use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw(log enable_include cache query));

use Data::ObjectMapper::Log;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    my ( $param, $option ) = @_;

    if( $option ) {
        for my $key ( keys %$option ) {
            $self->$key( $option->{$key} );
        }
    }

    $self->log( Data::ObjectMapper::Log->new() ) unless $self->log;

    $self->_init($param);

    return $self;
}

sub _init {}

sub transaction {}
sub namesep {}
sub datetime_parser {}
sub get_primary_key {}
sub get_column_info {}
sub get_unique_key {}
sub select {}
sub select_from_query_object {}
sub select_single {}
sub update {}
sub insert {}
sub create {}
sub delete {}
sub set_time_zone {}
sub iterator {}
sub stm_debug {}

1;
