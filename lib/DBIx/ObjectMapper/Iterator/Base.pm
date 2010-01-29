package DBIx::ObjectMapper::Iterator::Base;
use strict;
use warnings;

use overload
    '@{}' => sub { [ $_[0]->all ] },
    '0+'  => sub { $_[0]->size },
    fallback => 1,
    ;

sub new {
    my ( $class, $query, $callback ) = @_;
    return bless {
        cursor => 0,
        query => $query,
        callback => $callback && ref($callback) eq 'CODE' ? $callback : undef,
    }, $class;
}

sub cursor {
    my $self = shift;
    $self->{cursor} = shift if @_;
    return $self->{cursor};
}

sub size {}

sub next {}

sub reset {
    my $self = shift;
    $self->{cursor} = 0;
    return $self;
}

sub all {}

sub has_next { $_[0]->size > $_[0]->cursor }

sub first {
    my $self = shift;
    $self->reset if $self->cursor > 0;
    my $d = $self->next;
    $self->reset;
    return $d;
}

sub callback {
    my $self = shift;
    if( $self->{callback} ) {
        return $self->{callback}->($_[0], $self->{query});
    }
    else {
        return $_[0];
    }
}

sub DESTROY {
    my $self = shift;
    warn "DESTROY $self" if $ENV{MAPPER_DEBUG};
}

1;
