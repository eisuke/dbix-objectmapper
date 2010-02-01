package DBIx::ObjectMapper::Engine::DBI::Iterator;
use strict;
use warnings;
use Carp::Clan;
use base qw(DBIx::ObjectMapper::Iterator::Base);

sub engine   { $_[0]->{engine} }
sub query    { $_[0]->{query} }
sub _dbh     { $_[0]->{_dbh} }
sub _sth     { $_[0]->{_sth} }
sub _size    { $_[0]->{_size} }

sub new {
    my ( $class, $query, $engine, $callback ) = @_;
    my $self = $class->SUPER::new( $query, $callback );
    $self->{_size} = undef;
    $self->{engine} = $engine;
    $self->{_dbh}   = $engine->dbh;

    my ($key, $cache) = $self->engine->get_cache_id($query);
    if( $key and $cache ) {
        return DBIx::ObjectMapper::Iterator->new( $cache, $query, $callback );
    }
    elsif($key) {
        $self->{cache_key} = $key;
        $self->{cache_stack} = [];
    }

    return $self;
}

sub sth {
    my $self = shift;

    unless( $self->{_sth} ) {
        my ( $sql, @bind ) = $self->query->as_sql;
        my $sth = $self->engine->_prepare($sql);
        $sth->execute(@bind) or confess $sth->errstr;
        $self->engine->stm_debug($sql, @bind);
        my $size = $sth->rows;

        unless( $size ) {
            # FIX ME
            my $count_query = $self->query->clone;
            #my $count_query = $self->query;
            $count_query->column({ count => '*' });
            $count_query->order_by(undef);
            my $cnt = $self->engine->select_single($count_query);
            $size = $cnt->[0] if $cnt;
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
    return $class->new( $self->query, $self->engine, $self->{callback} );
}

sub _reset {
    my $self = shift;

    if( $self->{_sth} ) {
        if( $self->_sth->{Active} ) {
            if( $self->{cache_key} ) {
                while( my @r = $self->_sth->fetchrow_array ) {
                    push @{$self->{cache_stack}}, \@r;
                }
                $self->_set_cache($self->{cache_stack});
                $self->{cache_stack} = [];
            }
        }
        $self->_sth->finish;
        $self->{_sth} = undef;
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
      $self->engine->{cache_target_table}{ $self->query->from };

    if ( $self->{cache_key}
        and grep { $self->{cache_key} eq $_ } @$dr_cache_table )
    {
        $self->engine->log->info(
            '{QueryCache} Cache Set:' . $self->{cache_key} );
        $self->engine->cache->set( $self->{cache_key} => $cache )
    }
}

sub DESTROY {
    my $self = shift;
    warn "DESTROY $self" if $ENV{MAPPER_DEBUG};
    $self->_reset;
}

1;
