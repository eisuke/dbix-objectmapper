package DBIx::ObjectMapper::Session::Cache;
use strict;
use warnings;
use Scalar::Util qw(weaken);

our $weaken = 1;

sub new { bless +{}, $_[0] }

sub set {
    $_[0]->{$_[1]} = $_[2];
    weaken($_[0]->{$_[1]}) if $weaken;
    $_[2];
}

sub get { $_[0]->{$_[1]} }

sub remove { delete $_[0]->{$_[1]} }

sub clear {
    my $self = shift;
    $self->{$_} = undef for keys %$self;
}

sub DESTROY {
    my $self = shift;
    warn "DESTROY $self" if $ENV{MAPPER_DEBUG};
}

1;

=head1 NAME

DBIx::ObjectMapper::Session::Cache

=head1 AUTHOR

Eisuke Oishi

=head1 COPYRIGHT

Copyright 2010 Eisuke Oishi

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
