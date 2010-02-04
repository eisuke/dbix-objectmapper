package DBIx::ObjectMapper::Session::UnitOfWork;
use strict;
use warnings;
use Carp::Clan;
use Scalar::Util qw(refaddr blessed);
use Log::Any qw($log);

sub new {
    my ( $class, $cache, $query, $option ) = @_;

    my $self = bless {
        query_cnt   => 0,
        query       => $query,
        cache       => $cache || undef,
        objects     => +[],
        map_objects => +{},
        del_objects => +{},
        option      => $option || +{},
    }, $class;

    return $self;
}

sub query_cnt { $_[0]->{query_cnt} }

sub query { $_[0]->{query}->new( @_ ) }

sub cache { $_[0]->{cache} }

sub get {
    my ( $self, $t_class, $id, $option ) = @_;
    my $class_mapper = $t_class->__class_mapper__;

    my ( $key, @cond ) = $class_mapper->get_unique_condition($id);

    if( my $eagerload = $option->{eagerload} ) {
        my @eagerload
            = ref($eagerload) eq 'ARRAY' ? @{$eagerload} : ($eagerload);
        return $self->query($t_class)->eager_join(@eagerload)->where(@cond)
            ->execute->first;
    }
    elsif( my $cached_obj = $self->_get_cache($key) ) {
        $log->info("{UnitOfWork} Cache Hit: $key");
        if( $option->{share_object} || $self->{option}{share_object} ) {
            return $cached_obj;
        }
        else {
            my $result = $cached_obj->__mapper__->reducing;
            my $obj = $cached_obj->__class_mapper__->mapping( $result );
            return $self->add_storage_object($obj);
        }
    }
    else {
        my $obj = $class_mapper->find(@cond) || return;
        $self->{query_cnt}++;
        return $self->add_storage_object($obj);
    }
}

sub add_storage_object {
    my ( $self, $obj ) = @_;

    my $mapper = $obj->__mapper__;
    my $cache_key = $mapper->primary_cache_key;

    if ( $self->{option}{share_object}
        and my $cache_obj = $self->_get_cache($cache_key) )
    {
        return $cache_obj;
    }
    else {
        $mapper->change_status( 'persistent', $self );
        $self->add($obj);
        return $obj;
    }
}

sub add {
    my ( $self, $obj ) = @_;
    my $mapper = $obj->__mapper__;
    $mapper->change_status( 'pending', $self ) unless $mapper->is_persistent;
    # detached,expiredの場合はflushのところで無視される
    unless( exists $self->{map_objects}->{refaddr($obj)} ) {
        $self->_set_cache($mapper);
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
        next unless $obj;
        my $mapper = $obj->__mapper__;
        my $id = refaddr($obj);
        if( $mapper->is_pending ) {
            $mapper->save();
            $self->_clear_cache($mapper);
        }
        elsif( $mapper->is_persistent ) {
            if( exists $self->{del_objects}->{$id} ) {
                delete $self->{del_objects}->{$id};
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
    return unless $self->cache; # no_cache
    return $self->cache->get($key);
}

sub _set_cache {
    my ( $self, $mapper ) = @_;

    return unless $self->cache; # no_cache

    #my $result = $mapper->reducing;
    for my $key ( $mapper->cache_keys ) {
        $log->info("{UnitOfWork} Cache Set: $key");
        $self->cache->set( $key => $mapper->instance );
    }
}

sub _clear_cache {
    my ( $self, $mapper ) = @_;
    return unless $self->cache; # no_cache

    for my $key ( $mapper->cache_keys ) {
        $log->info("{UnitOfWork} Cache Remove: $key ");
        $self->cache->remove( $key );
    }
}

sub demolish {
    my $self = shift;
    $self->flush;
    for my $obj ( @{ $self->{objects} } ) {
        next unless $obj;
        $obj->__mapper__->demolish;
    }
    $self->{objects}     = +[];
    $self->{map_objects} = +{};
    $self->{del_objects} = +{};

    #$self->cache->clear;
    $self->{cache} = undef;
}

sub DESTROY {
    my $self = shift;
    $self->demolish;
    warn "DESTROY $self" if $ENV{MAPPER_DEBUG};
}

1;
