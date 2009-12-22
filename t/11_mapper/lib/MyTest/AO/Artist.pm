package MyTest::AO::Artist;
use strict;
use warnings;
use base qw(Class::Accessor::Fast);

__PACKAGE__->mk_accessors(qw(id firstname lastname));

sub fullname {
    my $self = shift;
    return $self->{firstname} . ' ' . $self->{lastname};
}

1;
