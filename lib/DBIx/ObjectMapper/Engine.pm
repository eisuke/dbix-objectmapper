package DBIx::ObjectMapper::Engine;
use strict;
use warnings;
use Log::Any qw($log);
use DBIx::ObjectMapper::Log;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->_init(@_);
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
