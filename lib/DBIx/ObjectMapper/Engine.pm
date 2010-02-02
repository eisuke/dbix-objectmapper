package DBIx::ObjectMapper::Engine;
use strict;
use warnings;
use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw(enable_include cache query));
use Log::Any qw($log);
use DBIx::ObjectMapper::Log;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    my ( $param, $option ) = @_;

    if( $option ) {
        for my $key ( keys %$option ) {
            $self->$key( $option->{$key} );
        }
    }
    $self->_init($param);

    return $self;
}

sub log { $log }

sub _init {}

sub transaction              { }
sub namesep                  { }
sub quote                    { }
sub driver                   { }
sub datetime_parser          { }
sub get_primary_key          { }
sub get_column_info          { }
sub get_unique_key           { }
sub get_tables               { }
sub select                   { }
sub select_from_query_object { }
sub select_single            { }
sub update                   { }
sub insert                   { }
sub create                   { }
sub delete                   { }
sub set_time_zone            { }
sub iterator                 { }

1;
