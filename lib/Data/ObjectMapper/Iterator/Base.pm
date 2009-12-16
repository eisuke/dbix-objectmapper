package Data::ObjectMapper::Iterator::Base;
use strict;
use warnings;

use overload
    '@{}' => sub { [ $_[0]->all ] },
    '0+'  => sub { $_[0]->size },
    fallback => 1,
    ;

sub new { bless { cursor => 0 }, $_[0] }

sub cursor {
    my $self = shift;
    $self->{cursor} = shift if @_;
    return $self->{cursor};
}

sub size {}

sub count { shift->size }

sub next {}

sub reset {}

sub all {}

sub has_next { $_[0]->size > $_[0]->cursor }

sub first {
    my $self = shift;
    $self->reset if $self->cursor > 0;
    my $d = $self->next;
    $self->reset;
    return $d;
}

1;
