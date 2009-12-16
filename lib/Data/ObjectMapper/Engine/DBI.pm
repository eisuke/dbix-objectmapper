package Data::ObjectMapper::Engine::DBI;
use strict;
use warnings;
use Carp::Clan;
use DBI;
use Data::Dumper;
use Digest::MD5;

use base qw(Data::ObjectMapper::Engine);
use Data::ObjectMapper::SQL;
use Data::ObjectMapper::Utils;
use Data::ObjectMapper::Engine::DBI::Iterator;
use Data::ObjectMapper::Engine::DBI::Driver;

use Data::ObjectMapper::Engine::DBI::Connector; # subclass of DBIx::Connector

sub _init {
    my $self = shift;
    my $param = shift || $self->log->exception('invalid parameter.');

    my @connect_info;
    my $connect_do;
    my $option;

    if( ref $param eq 'ARRAY' ){
        @connect_info = @$param[0..2];
        $option = $param->[3] if $param->[3];
        $connect_do = $param->[4] if $param->[4];
    }
    elsif( ref $param eq 'HASH' ) {
        @connect_info =
          ( $param->{dsn}, $param->{username}, $param->{password} );
        $connect_do = $param->{on_connect_do} if exists $param->{on_connect_do};
        $option = $param->{option};
    }
    else {
        $self->log->exception('invalid parameter.');
    }

    $self->{connect_do}
        = ref $connect_do eq 'ARRAY' ? $connect_do : [$connect_do]
        if $connect_do;

    $self->init_option($option);

    push @connect_info,
      {
        AutoCommit => exists $option->{AutoCommit}
        ? delete $option->{AutoCommit}
        : 1,
        RaiseError         => 1,
        PrintError         => 0,
        ShowErrorStatement => 1,
        ConnectDo          => $self->{connect_do},
        %{ $option || {} }
      };

    $self->{connect_info} = \@connect_info;
    my $connector
        = Data::ObjectMapper::Engine::DBI::Connector->new(@connect_info);
    $self->{connector} = $connector;

    my $type = $connector->driver->{driver} || confess 'Driver Not Found.';

    $self->{query} ||= Data::ObjectMapper::SQL->new($type);

    $self->{driver} = Data::ObjectMapper::Engine::DBI::Driver->new(
        $type,
        db_schema       => $self->{db_schema}       || undef,
        sql             => $self->query,
        log             => $self->log,
        datetime_parser => $self->{datetime_parser} || undef,
    );

    return $self;
}

sub init_option {
    my ( $self, $option) = @_;

    if( delete $option->{disable_prepare_caching} ){
        $self->{disable_prepare_caching} = 1;
    }

    if( my $db_schema = delete $option->{db_schema} ) {
        $self->{db_schema} = $db_schema;
    }

    if( my $datetime_parser = delete $option->{datetime_parser} ) {
        $self->{datetime_parser} = $datetime_parser;
    }

    $self->{connection_mode}
        = $option->{connection_mode}
        ? delete $option->{connection_mode}
        : 'fixup';

    $self->{iterator} ||= 'Data::ObjectMapper::Engine::DBI::Iterator';

    $self->{cache_target_table} = +{};
}


### Driver
sub driver          { $_[0]->{driver} }
sub iterator        { $_[0]->{iterator} }
sub query           { $_[0]->{query} }
sub namesep         { $_[0]->driver->namesep }
sub datetime_parser { $_[0]->driver->datetime_parser }
sub set_time_zone   { $_[0]->driver->set_time_zone( $_[0]->dbh, $_[1] ) }

### Database Handle
sub dbh { $_[0]->{connector}->dbh }

sub dbh_do {
    my $self = shift;
    return $self->{connector}->run( $self->{connection_mode} => @_ );
}

sub _prepare {
    my ( $self, $sql ) = @_;
    return $self->dbh_do(
        sub {
            my $dbh = $self->dbh; # for on_connect_do
            $self->{disable_prepare_caching}
                ? $dbh->prepare($sql)
                : $dbh->prepare_cached( $sql, undef, 3 );
        }
    );
}

sub transaction {
    my $self = shift;
    my $code = shift;
    confess "it must be CODE reference" unless $code and ref $code eq 'CODE';
    return $self->{connector}->txn( $self->{connection_mode} => $code );
}

sub savepoint {
    my $self = shift;
    my $code = shift;
    confess "it must be CODE reference" unless ref $code eq 'CODE';
    return $self->{connector}->txn( $self->{connection_mode} => $code );
}

### Metadata
sub get_primary_key {
    my ( $self, $table ) = @_;
    return $self->driver->get_primary_key($self->dbh, $table);
}

sub get_column_info {
    my ( $self, $table ) = @_;
    return $self->driver->get_column_info($self->dbh, $table);
}

sub get_unique_key {
    my ( $self, $table ) = @_;
    return $self->driver->get_table_uniq_info($self->dbh, $table);
}

### Query

sub select {
    my ( $self, $query, $callback ) = @_;
    unless ( ref $query eq ref $self->query ) {
        $query = $self->_as_query_object( 'select', $query );
    }
    return $self->iterator->new( $query, $self, $callback );
}

sub select_single {
    my $self = shift;
    return $self->_select('fetchrow_arrayref', @_);
}

sub _select {
    my ( $self, $meth, $query, $callback ) = @_;

    unless ( ref $query eq ref $self->query ) {
        $query = $self->_as_query_object('select', $query);
    }

    my ($key, $cache) = $self->get_cache_id($query);

    my $result;
    if( $key and $cache ) {
        $result = $cache;
    }
    else {
        my ( $sql, @bind ) = $query->as_sql;
        $self->stm_debug($sql, @bind);
        my $sth = $self->_prepare($sql);
        $sth->execute(@bind) or $self->log->exception($sth->errstr);
        $result = $sth->$meth;
        $sth->finish;
    }

    if( $key and !$cache and $result ) {
        $self->log->driver_trace('[QueryCache]Cache Set:' . $key);
        $self->cache->set( $key => $result );
    }

    return $callback && ref($callback) eq 'CODE'
        ? $callback->( $result, $query )
        : $result;
}

sub _as_query_object {
    my ($self, $action, $query ) = @_;
    return $self->query->$action( %$query );
}

sub update {
    my ( $self, $query, $callback ) = @_;

    unless ( ref $query eq ref $self->query ) {
        $query = $self->_as_query_object('update', $query);
    }

    $callback->($query) if $callback and ref($callback) eq 'CODE';

    if ( my $keys = $self->{cache_target_table}{ $query->table } ) {
        $self->{cache_target_table}{ $query->table } = [];
        $self->log->driver_trace(
            '[QueryCache]Cache Remove : ' . join( ', ', @$keys ) );
        $self->cache->remove( $_ ) for @$keys;
    }

    my ( $sql, @bind ) = $query->as_sql;
    $self->stm_debug($sql, @bind);
    return $self->dbh_do(
        sub{
            my $dbh = $self->dbh; # for on_connect_do
            $dbh->do($sql, {}, @bind);
        },
    );
}

sub insert {
    my ( $self, $query, $callback, $primary_keys ) = @_;

    unless ( ref $query eq ref $self->query ) {
        $query = $self->_as_query_object('insert', $query);
    }

    $callback->($query) if $callback and ref($callback) eq 'CODE';

    my ( $sql, @bind ) = $query->as_sql;
    $self->stm_debug($sql, @bind);
    $self->dbh_do( sub {  $self->dbh->do( $sql, {}, @bind ) } );

    my $ret_id = ref($query->values) eq 'HASH' ? $query->values : +{};
    if( $primary_keys ) {
        for my $pk (@$primary_keys) {
            unless( exists $query->{values}->{$pk} ) {
                $ret_id->{$pk} = $self->driver->last_insert_id(
                    $self->dbh,
                    $query->table,
                    $pk
                );
            }
        }
    }

    return $ret_id;
}

sub delete {
    my ( $self, $query, $callback ) = @_;

    unless ( ref $query eq ref $self->query ) {
        $query = $self->_as_query_object('delete', $query);
    }

    $callback->($query) if $callback and ref($callback) eq 'CODE';

    if ( my $keys = $self->{cache_target_table}{ $query->table } ) {
        $self->{cache_target_table}{ $query->table } = [];
        $self->log->driver_trace(
            '[QueryCache]Cache Remove : ' . join( ', ', @$keys ) );
        $self->cache->remove( $_ ) for @$keys;
    }

    my ( $sql, @bind ) = $query->as_sql;
    $self->stm_debug($sql, @bind);
    return $self->dbh_do( sub {  $self->dbh->do( $sql, {}, @bind ) } );
}

# XXXX TODO CREATE TABLE
sub create {  }

sub stm_debug {
    my ( $self, $sql, @bind ) = @_;

    if( $self->log->is_driver_trace ) {
        my $string = $sql . ': ';
        $string .= join( ', ', map { defined $_ ? $_ : 'undef' } @bind )
          if @bind;
        $self->log->driver_trace($string);
    }
}

sub get_cache_id {
    my ( $self, $query ) = @_;

    return
        if !$self->cache
            or !$query->from
            or ( $query->limit and !$query->order_by );

    my @target_tables = $self->__get_table_name($query->from);
    push @target_tables, $self->__get_table_name( $query->{joins} )
        if @{$query->{joins}};

    local $Data::Dumper::Sortkeys = 1;
    my $key = Digest::MD5::md5_hex(ref($self) . Data::Dumper::Dumper($query));
    if( my $cache = $self->cache->get($key) ) {
        $self->log->driver_trace( '[QueryCache]Cache Hit : ' . $key );
        return ($key, $cache);
    }

    push @{$self->{cache_target_table}{$_}}, $key for @target_tables;

    return $key;
}

sub __get_table_name {
    my ( $self, $from ) = @_;

    if( ref($from) eq 'ARRAY' ) {
        my @res;
        for my $f ( @$from ) {
            if( ref( $f ) eq 'ARRAY' ){
                push @res, $f->[0];
            }
            else{
                push @res, $f;
            }
        }
        return @res;
    }
    else {
        return $from;
    }
}

1;
