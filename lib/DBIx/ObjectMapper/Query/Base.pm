package DBIx::ObjectMapper::Query::Base;
use strict;
use warnings;
use Scalar::Util qw(weaken);
use Carp::Clan qw/^DBIx::ObjectMapper/;

sub new {
    my $class = shift;
    my $metadata = shift || confess 'usage: ' . $class . '->new($metadata)';
    my $callback = shift || undef;
    my ( $before, $after ) = @_;
    my $self = bless {
        metadata => $metadata,
        callback => $callback,
        before   => $before || sub { },
        after    => $after || sub { },
    }, $class;

    weaken($self->{metadata});
    return $self;
}

sub metadata { $_[0]->{metadata} }
sub engine   { $_[0]->metadata->engine }
sub callback { $_[0]->{callback} }

sub builder {
    my $self = shift;
    $self->{builder} = shift if @_;
    return $self->{builder};
}

sub execute { die "Abstract Method" }

sub as_sql {
    my $self = shift;
    return $self->builder->as_sql(@_);
}

sub DESTROY {
    my $self = shift;
    warn "DESTROY $self" if $ENV{MAPPER_DEBUG};
}

1;
