package MyTest::Basic::Artist;
use strict;
use warnings;
use base qw(Class::Accessor::Fast);

__PACKAGE__->mk_accessors(qw(id firstname lastname));

sub new {
    my $class = shift;
    my %attr = @_;

    bless \%attr, $class;
}

sub fullname {
    my $self = shift;
    return $self->firstname . ' ' . $self->lastname;
}

1;
