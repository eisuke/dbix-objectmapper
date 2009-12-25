package Data::ObjectMapper::Session::UnitOfWork;
use strict;
use warnings;
use Carp::Clan;
use Scalar::Util qw(refaddr blessed);

sub new {
    my ( $class, $cache ) = @_;

    bless {
        cache       => $cache,
        persistent  => +{},
        detached    => +{},
        pending     => +{},
        objects_map => +{},
        objects     => +[],
    }, $class;
}

sub get_status {
    my ( $self, $obj ) = @_;
    return
           $self->is_persistent($obj)
        || $self->is_detached($obj)
        || $self->is_pending($obj)
        || 'transient';
}

sub is_modified {
    my ( $self, $obj ) = @_;

    return unless $self->is_persistent($obj);
    my $mapper = $obj->__mapper__;
    my $reduce_data = $mapper->reducing($obj);
    my $original_data
        = $self->_get_cache( $mapper->primary_cache_key_from_instance );
    if (grep { $reduce_data->{$_} ne $original_data->{$_} } keys %$reduce_data)
    {
        return 1;
    }
    else {
        return 0;
    }
}

sub is_persistent {
    my ( $self, $obj ) = @_;
    $self->{persistent}{refaddr($obj)};
}

sub is_detached {
    my ( $self, $obj ) = @_;
    $self->{detached}{refaddr($obj)};
}

sub is_pending {
    my ( $self, $obj ) = @_;
    $self->{pending}{refaddr($obj)};
}

sub get {
    my ( $self, $t_class, $id ) = @_;
    $t_class = ref($t_class) if blessed($t_class);
    my $mapper = $t_class->__mapper__;

    my ( $key, @cond ) = $mapper->get_unique_condition($id);
    my $obj;
    if( my $cache = $self->_get_cache($key) ) {
        $obj = $mapper->mapping($cache);
    }
    else {
        $obj = $mapper->find(@cond) || return;
    }

    $self->{persistent}{refaddr($obj)} = 1;
    $self->_set_cache($obj);
    $self->add( $obj );
}

sub add {
    my ( $self, $obj ) = @_;
    $self->{pending}{refaddr($obj)} = 1 unless $self->is_persistent($obj);
    $self->{objects}{refaddr($obj)} = $obj;
    return $obj;
}

sub detach {
    my ( $self, $obj ) = @_;
    my $id = refaddr($obj);
    delete $self->{$_}{$id} for qw(persistent pending);
    $self->{detached}{$id} = 1;
    $self->_clear_cache($obj);
}

sub flush {
    my ( $self, $obj ) = @_;

    if( $self->is_persistent($obj) ) {
        $self->_update($obj);
    }
    elsif( $self->is_pending($obj) ) {
        $self->_save($obj);
    }
    else {

    }
}

sub _update {
    my ( $self, $obj ) = @_;

    confess "XXXX" unless $self->is_persistent($obj);
    my $mapper = $obj->__mapper__;
    my $reduce_data = $mapper->reducing;

    my $original_data
        = $self->_get_cache( $mapper->primary_cache_key_from_instance );

    my %modified_data = map { $_ => $reduce_data->{$_} }
        grep { $reduce_data->{$_} ne $original_data->{$_} }
            keys %$reduce_data;

    confess "XXXXX" unless %modified_data;

    my $uniq_cond = $mapper->identity_condition;
    my $r = $mapper->from->update->set(%modified_data)->where(@$uniq_cond)
        ->execute();
    $mapper->modify($r);
}

sub flush_all {
    my $self = shift;


}

sub _save {
    my ( $self, $obj ) = @_;

    confess "XXXX" if $self->is_persistent($obj);
    my $mapper = $obj->__mapper__;
    my $reduce_data = $mapper->reducing($obj);
    my $comp_result
        = $mapper->from->insert->values(%$reduce_data)->execute();
    $obj->modify($comp_result);
}

sub delete {
    my $self = shift;
    my $obj  = shift;

    confess "XXXX" unless $self->is_persistent($obj);
    my $mapper = $obj->__mapper__;
    my $uniq_cond = $mapper->identity_condition;
    $mapper->from->delete->where(@$uniq_cond)->execute();
    $self->detach( $obj );
}


sub _get_cache {
    my ( $self, $key ) = @_;
    return $self->cache->get($key);
}

sub _set_cache {
    my ( $self, $obj ) = @_;
    my $mapper = $obj->__mapper__;
    my $result = $mapper->reducing;
    $self->cache->set( $mapper->primary_cache_key($result) => $result );
    $self->cache->set( $_ => $result ) for $mapper->unique_cache_keys($result);
}

sub _clear_cache {
    my ( $self, $obj ) = @_;
    $self->cache->remove( $self->_get_primary_cache_key($obj) );
    $self->cache->remove( $_ ) for $self->_get_unique_cache_keys($obj);
}

1;
