package Data::ObjectMapper::Session::UnitOfWork;
use strict;
use warnings;
use Carp::Clan;
use Scalar::Util qw(refaddr blessed);

sub new {
    my ( $class, $cache ) = @_;

    bless {
        cache       => $cache,
        objects     => +[],
        map_objects => +{},
        del_objects => +{},
    }, $class;
}

sub cache { $_[0]->{cache} }

sub get {
    my ( $self, $t_class, $id ) = @_;
    my $class_mapper = $t_class->__class_mapper__;

    $self->flush;
    my ( $key, @cond ) = $class_mapper->get_unique_condition($id);
    my $obj;
    if( my $cache = $self->_get_cache($key) ) {
        $obj = $class_mapper->mapping($cache);
    }
    else {
        $obj = $class_mapper->find(@cond) || return;
    }

    my $mapper = $obj->__mapper__;
    $mapper->change_status( 'persistent', $self );
    $self->_set_cache($mapper);
    $self->add($obj);
    return $obj;
}

sub add {
    my ( $self, $obj ) = @_;
    my $mapper = $obj->__mapper__;
    $mapper->change_status( 'pending', $self ) unless $mapper->is_persistent;
    unless( exists $self->{map_objects}->{refaddr($obj)} ) {
        push @{$self->{objects}}, $obj;
        $self->{map_objects}->{refaddr($obj)} = $#{$self->{objects}};
    }
    return $obj;
}

sub delete {
    my ( $self, $obj ) = @_;
    my $elm = $self->{map_objects}->{refaddr($obj)};
    $self->{del_objects}->{refaddr($obj)} = $elm;
    return $obj;
}

sub detach {
    my ( $self, $obj ) = @_;
    my $mapper = $obj->__mapper__;
    $mapper->change_status('detached');
    $self->_clear_cache($mapper);
}

sub flush {
    my ( $self ) = @_;
    for my $obj (@{$self->{objects}}) {
        my $mapper = $obj->__mapper__;
        my $id = refaddr($obj);
        if( $mapper->is_pending ) {
            $mapper->save();
            $self->_clear_cache($mapper);
        }
        elsif( $mapper->is_persistent ) {
            if( delete $self->{del_objects}->{$id} ) {
                $mapper->delete();
            }
            elsif( $mapper->is_modified ) {
                $mapper->update();
            }
            $self->_clear_cache($mapper);
        }
    }
}

sub _get_cache {
    my ( $self, $key ) = @_;
    return $self->cache->get($key);
}

sub _set_cache {
    my ( $self, $mapper ) = @_;
    my $result = $mapper->reducing;
    $self->cache->set( $_ => $result ) for $mapper->cache_keys;
}

sub _clear_cache {
    my ( $self, $mapper ) = @_;
    $self->cache->remove( $_ ) for $mapper->cache_keys;
}

sub demolish {
    my $self = shift;
    $self->flush;
    for my $obj ( @{ $self->{objects} } ) {
        $obj->__mapper__->demolish;
    }
    $self->{objects} = +[];
}

sub DESTROY {
    my $self = shift;
    warn "DESTROY $self" if $ENV{DOM_CHECK_DESTROY};
    $self->demolish;
}

1;
