package DBIx::ObjectMapper::Query::Base;
use strict;
use warnings;
use Scalar::Util qw(weaken blessed);
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

# By default, OM supports mutable query building.  clone() allows us to extend
# queries without affecting the original queries.
sub clone {
    my $self = shift;
    my ($clone_hash, $clone_array, $clone_element);

    $clone_hash = sub {
        my $hash = shift;
        return {
            map {
                $_ => $clone_element->($hash->{$_})
            } keys %$hash
        };
    };

    $clone_array = sub {
        my $array = shift;
        return [
            map {
                $clone_element->($_)
            } @$array
        ];
    };

    $clone_element = sub {
        my $element = shift;

        if (!ref $element || ref $element eq 'CODE') {
            return $element;
        }
        elsif (blessed $element && $element->can('clone')) {
            return $element->clone;
        }
        elsif (blessed $element) {
            return $element;
        }
        elsif (ref $element eq 'HASH') {
            return $clone_hash->($element);
        }
        elsif (ref $element eq 'ARRAY') {
            return $clone_array->($element);
        }
        else {
            use Data::Dumper;
            die "I do not know how to clone: " . Dumper($element);
        }
    };

    return bless($clone_hash->($self), blessed $self);
}

sub DESTROY {
    my $self = shift;
    warn "DESTROY $self" if $ENV{MAPPER_DEBUG};
}

1;
