package Data::ObjectMapper::Session::UnitOfWork;
use strict;
use warnings;
use Carp::Clan;
use Scalar::Util qw(refaddr blessed);

sub new {
    my ( $class, $cache ) = @_;

    bless {
        cache       => $cache,
        objects_map => +{},
        objects     => +[],
    }, $class;
}

sub cache { $_[0]->{cache} }

sub get {
    my ( $self, $t_class, $id ) = @_;
    $t_class = ref($t_class) if blessed($t_class);
    my $class_mapper = $t_class->__mapper__;

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
    unless( exists $self->{objects_map}->{refaddr($obj)} ) {
        push @{$self->{objects}}, $obj;
        $self->{objects_map}->{refaddr($obj)} = $#{$self->{objects}};
    }
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
    for my $obj ( @{$self->{objects}} ) {
        my $mapper = $obj->__mapper__;
        if( $mapper->is_pending ) {
            $mapper->save();
            $self->_clear_cache($mapper);
        }
        elsif( $mapper->is_persistent and $mapper->is_modified ) {
            $mapper->update();
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

sub DESTROY {
    my $self = shift;
    warn "$self DESTROY" if $ENV{DOM_CHECK_DESTROY};
    $self->flush;
    for my $obj ( @{ $self->{objects} } ) {
        $obj->__mapper__->demolish;
    }
    $self->{objects} = +[];
}

1;
