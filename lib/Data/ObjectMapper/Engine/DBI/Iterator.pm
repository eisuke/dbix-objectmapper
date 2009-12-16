package Data::ObjectMapper::Engine::DBI::Iterator;
use strict;
use warnings;
use Carp::Clan;
use base qw(Data::ObjectMapper::Iterator::Base);

sub driver   { $_[0]->{driver} }
sub query    { $_[0]->{query} }
sub _sth     { $_[0]->{_sth} }
sub _size    { $_[0]->{_size} }

sub new {
    my ( $class, $query, $driver, $callback ) = @_;
    my $self = $class->SUPER::new();
    $self->{_size} = undef;
    $self->{driver} = $driver;
    $self->{query} = $query;
    $self->{callback}
        = $callback && ref($callback) eq 'CODE' ? $callback : undef;

    my ($key, $cache) = $self->driver->get_cache_id($query);
    if( $key and $cache ) {
        return Data::ObjectMapper::Iterator->new( $cache, $callback );
    }
    elsif($key) {
        $self->{cache_key} = $key;
        $self->{cache_stack} = [];
    }

    return $self;
}

sub callback {
    my $self = shift;
    if( $self->{callback} ) {
        return $self->{callback}->($_[0], $self->query);
    }
    else {
        return $_[0];
    }
}

sub sth {
    my $self = shift;

    unless( $self->_sth ) {
        my ( $sql, @bind ) = $self->query->as_sql;
        $self->driver->stm_debug($sql, @bind);
        my $sth = $self->driver->_prepare($sql);
        $sth->execute(@bind) or confess $sth->errstr;
        my $size = $sth->rows;

        unless( $size ) {
            # FIX ME
            #if( $self->query->limit ) {
            #    $size = $self->query->limit->[0];
            #}
            #else {
            #    my $count_query = $self->query->clone;
            #    $count_query->column({ count => '*' });
            #    $count_query->order_by(undef);
            #    my $cnt = $self->driver->select_single($count_query);
            #    if( $cnt ) {
            #        $size = $cnt->[0];
            #    }
            #    else {
            #        $size = 2**48; # fuck.
            #        if( $self->{cache_key} ) {
            #            delete $self->{cache_key};
            #            delete $self->{cache_stack};
            #        }
            #    }
            #}
        }
        $self->{_size} = $size;
        $self->{_sth} = $sth;
    }

    return $self->{_sth};
}

sub size {
    my $self = shift;
    $self->sth;
    return $self->_size;
}

sub next {
    my $self = shift;

    if( my @r = $self->sth->fetchrow_array ) {
        $self->{cursor}++;
        push @{$self->{cache_stack}}, \@r if $self->{cache_key};
        return $self->callback(\@r);
    }
    else {
        $self->_reset;
        return;
    }
}

sub reset {
    my $self = shift;
    $self->_reset;
    my $class = ref($self);
    return $class->new( $self->query, $self->driver, $self->{callback} );
}

sub _reset {
    my $self = shift;

    if( $self->_sth ) {
        if( $self->_sth->{Active} ) {
            if( $self->{cache_key} ) {
                while( my @r = $self->_sth->fetchrow_array ) {
                    push @{$self->{cache_stack}}, \@r;
                }
                $self->_set_cache($self->{cache_stack});
                $self->{cache_stack} = [];
            }
            $self->_sth->finish;
        }

        $self->_sth(undef);
    }

    $self->cursor(0);
}

sub first {
    my $self = shift;
    $self->_reset;
    my $d = $self->next;
    $self->_reset;
    return $d;
}

sub all {
    my $self = shift;
    $self->_reset;
    my $result = $self->sth->fetchall_arrayref;
    $self->_set_cache($result);

    return map{ $self->callback($_) } @$result;
}

sub _set_cache {
    my ( $self, $cache ) = @_;

    my $dr_cache_table =
      $self->driver->{cache_target_table}{ $self->query->from };

    if ( $self->{cache_key}
        and grep { $self->{cache_key} eq $_ } @$dr_cache_table )
    {
        $self->driver->log->driver_trace(
            '[QueryCache]Cache Set:' . $self->{cache_key} );
        $self->driver->cache->set( $self->{cache_key} => $cache )
    }
}

sub DESTROY {
    my $self = shift;
    $self->_reset;
}

1;
