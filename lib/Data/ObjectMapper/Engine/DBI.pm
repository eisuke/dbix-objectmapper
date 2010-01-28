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
use Data::ObjectMapper::Engine::DBI::Transaction;

use Data::ObjectMapper::Engine::DBI::Connector; # subclass of DBIx::Connector

sub _init {
    my $self = shift;
    my $param = shift || confess 'invalid parameter.';

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
        confess 'invalid parameter.';
    }

    $self->{connect_do}
        = $connect_do
        ? ref $connect_do eq 'ARRAY'
            ? $connect_do
            : [$connect_do]
        : [];

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
    $self->{driver_type} = $type;
    $self->{time_zone} = $option->{time_zone} || undef;

    $self->{driver} = Data::ObjectMapper::Engine::DBI::Driver->new(
        $type,
        $connector->dbh,
        db_schema       => $self->{db_schema}       || undef,
        namesep         => $self->{namesep}         || undef,
        quote           => $self->{quote}           || undef,
        sql             => $self->query,
        log             => $self->log,
        datetime_parser => $self->{datetime_parser} || undef,
        time_zone       => $self->{time_zone},
    );

    if ( $self->{time_zone}
        and my $tzq = $self->{driver}->set_time_zone_query )
    {
        push @{ $self->{connect_do} }, $tzq;
    }

    $self->init_option($option);

    return $self;
}

sub init_option {
    my ( $self, $option) = @_;

    if( delete $option->{disable_prepare_caching} ){
        $self->{disable_prepare_caching} = 1;
    }

    for my $name ( qw(db_schema namesep quote datetime_parser) ) {
        $self->{$name} = $option->{$name} if exists $option->{$name};
    }

    $self->{connection_mode}
        = $option->{connection_mode}
        ? delete $option->{connection_mode}
        : $self->driver->default_connection_mode;

    $self->{iterator} ||= 'Data::ObjectMapper::Engine::DBI::Iterator';

    $self->{cache_target_table} = +{};
}


### Driver
sub driver          { $_[0]->{driver} }
sub driver_type     { $_[0]->{driver_type} }
sub iterator        { $_[0]->{iterator} }
sub query           { $_[0]->{query} }
sub namesep         { $_[0]->driver->namesep }
sub quote           { $_[0]->driver->quote }
sub datetime_parser { $_[0]->driver->datetime_parser }
sub time_zone       { $_[0]->{time_zone} }

### Database Handle
sub dbh { $_[0]->{connector}->dbh }

sub dbh_do {
    my $self = shift;
    return $self->{connector}->run( $self->{connection_mode} => @_ );
}

sub transaction {
    my $self = shift;
    if (@_) {
        my $code = shift;
        confess "it must be CODE reference"
            unless $code and ref $code eq 'CODE';
        return $self->{connector}->txn( $self->{connection_mode} => $code );
    }
    else {
        return Data::ObjectMapper::Engine::DBI::Transaction->new(
            $self->dbh, $self->{connector}->driver, $self->log,
        );
    }
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

sub get_foreign_key {
    my ( $self, $table ) = @_;
    return $self->driver->get_table_fk_info($self->dbh, $table);
}

sub get_tables {
    my ( $self ) = @_;
    return $self->driver->get_tables($self->dbh);
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
    #return $self->_select('fetchrow_arrayref', @_);

    my ( $query, $callback ) = @_;

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
        $result = $self->dbh->selectrow_arrayref($sql, +{}, @bind);
    }

    if( $key and !$cache and $result ) {
        $self->log->info('[QueryCache]Cache Set:' . $key);
        $self->cache->set( $key => $result );
    }

    return $callback && ref($callback) eq 'CODE'
        ? $callback->( $result, $query )
        : $result;
}

=pod

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
        $sth->execute(@bind) || confess $sth->errstr;
        $result = $sth->$meth;
        $sth->finish;
    }

    if( $key and !$cache and $result ) {
        $self->log->info('[QueryCache]Cache Set:' . $key);
        $self->cache->set( $key => $result );
    }

    return $callback && ref($callback) eq 'CODE'
        ? $callback->( $result, $query )
        : $result;
}

=cut

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
        $self->log->info(
            '{QueryCache} Cache Remove : ' . join( ', ', @$keys ) );
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
            unless ( defined $query->{values}->{$pk} ) {
                $ret_id->{$pk} = $self->driver->last_insert_id(
                    $self->dbh,
                    $query->into,
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
        $self->log->info(
            '{QueryCache} Cache Remove : ' . join( ', ', @$keys ) );
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

    if( $self->log->is_info ) {
        my $string = $sql . ': (';
        $string .= join( ', ', map { defined $_ ? $_ : 'undef' } @bind )
          if @bind;
        $string .= ')';
        $self->log->info( '{SQL} ' . $string);
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
        $self->log->info( '{QueryCache} Cache Hit : ' . $key );
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
