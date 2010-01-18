package Data::ObjectMapper::Session::UnitOfWork;
use strict;
use warnings;
use Carp::Clan;
use Scalar::Util qw(refaddr blessed);
use Log::Any qw($log);

sub new {
    my ( $class, $cache, $query ) = @_;

    bless {
        query_cnt   => 0,
        query       => $query,
        cache       => $cache,
        objects     => +[],
        map_objects => +{},
        del_objects => +{},
    }, $class;
}

sub query_cnt { $_[0]->{query_cnt} }

sub query { $_[0]->{query}->new( @_ ) }

sub cache { $_[0]->{cache} }

sub get {
    my ( $self, $t_class, $id, $option ) = @_;
    my $class_mapper = $t_class->__class_mapper__;

    $self->flush;
    my ( $key, @cond ) = $class_mapper->get_unique_condition($id);
    my $obj;
    if( my $cache = $self->_get_cache($key) ) {
        $log->info("{UnitOfWork} Cache Hit: $key");
        $obj = $class_mapper->mapping($cache);
    }
    elsif( my $eagerload = $option->{eagerload} ) {
        my @eagerload
            = ref($eagerload) eq 'ARRAY' ? @{$eagerload} : ($eagerload);
        return $self->query($t_class)->eager_join(@eagerload)->where(@cond)
            ->execute->first;
    }
    else {
        $obj = $class_mapper->find(@cond) || return;
        $self->{query_cnt}++;
    }

    return $self->add_storage_object($obj);
}

sub add_storage_object {
    my ( $self, $obj ) = @_;

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
                $self->_clear_cache($mapper);
            }
            elsif( $mapper->is_modified ) {
                $mapper->update();
                $self->_clear_cache($mapper);
            }
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
    for my $key ( $mapper->cache_keys ) {
        $log->info("{UnitOfWork} Cache Set: $key");
        $self->cache->set( $key => $result );
    }
}

sub _clear_cache {
    my ( $self, $mapper ) = @_;
    for my $key ( $mapper->cache_keys ) {
        $log->info("{UnitOfWork} Cache Remove: $key");
        $self->cache->remove( $key );
    }
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
    $log->debug("DESTROY $self");
    $self->demolish;
}

1;
