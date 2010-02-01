package DBIx::ObjectMapper::Engine::DBI;
use strict;
use warnings;
use Carp::Clan;
use DBI;
use Data::Dumper;
use Digest::MD5;

use base qw(DBIx::ObjectMapper::Engine);
use DBIx::ObjectMapper::SQL;
use DBIx::ObjectMapper::Utils;
use DBIx::ObjectMapper::Engine::DBI::Iterator;
use DBIx::ObjectMapper::Engine::DBI::Driver;
use DBIx::ObjectMapper::Engine::DBI::Transaction;

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

    push @connect_info, {
        AutoCommit => exists $option->{AutoCommit}
        ? delete $option->{AutoCommit}
        : 1,
        RaiseError         => 1,
        PrintError         => 0,
        ShowErrorStatement => 1,
        %{ $option || {} }
    };

    $self->{connect_info} = \@connect_info;
    $self->{driver_type} = undef;
    $self->{driver}      = undef;
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

    $self->{iterator} ||= 'DBIx::ObjectMapper::Engine::DBI::Iterator';

    $self->{time_zone} = $option->{time_zone} || undef;

    $self->{cache_target_table} = +{};
}


### Driver
sub iterator        { $_[0]->{iterator} }
sub namesep         { $_[0]->driver->namesep }
sub quote           { $_[0]->driver->quote }
sub datetime_parser { $_[0]->driver->datetime_parser }
sub time_zone       { $_[0]->{time_zone} }

sub driver_type     {
    my $self = shift;
    $self->dbh unless $self->{driver_type};
    return $self->{driver_type};
}

sub query {
    my $self = shift;
    $self->dbh unless $self->{query};
    return $self->{query};
}

sub driver {
    my $self = shift;
    $self->connect unless $self->connected;
    return $self->{driver};
}


### Database Handle

sub DESTROY {
    my $self = shift;
    # some databases need this to stop spewing warnings
    if (my $dbh = $self->{_dbh}) {
        $self->_verify_pid;
        local $@;
        eval { $dbh->disconnect };
    }
    $self->{_dbh} = undef;
}

sub dbh {
    my $self = shift;
    $self->connect unless $self->connected;
    return $self->{_dbh};
}

sub connected {
    my $self = shift;

    if ( my $dbh = $self->{_dbh} ) {
        if( defined $self->{_tid} && $self->{_tid} != threads->tid ) {
            $self->{_dbh} = undef;
            return 0;
        }
        else {
            $self->_verify_pid;
            return 0 if !$self->{_dbh};
        }

        return ($dbh->{Active} && $dbh->ping);
    }

    return 0;
}

sub connect {
    my $self = shift;
    $self->{_pid} = $$;
    $self->{_tid} = threads->tid if $INC{'threads.pm'};
    $self->{_dbh} = $self->_connect;
}

sub _verify_pid {
    my ($self) = @_;

    return if defined $self->{_pid} && $self->{_pid} == $$;

    $self->{_dbh}->{InactiveDestroy} = 1;
    $self->{_dbh} = undef;
    return;
}

sub _connect {
    my $self = shift;

    my $dbh = do {
        if ($INC{'Apache/DBI.pm'} && $ENV{MOD_PERL}) {
            local $DBI::connect_via = 'connect'; # Disable Apache::DBI.
            DBI->connect( @{ $self->{connect_info} } );
        } else {
            DBI->connect( @{ $self->{connect_info} } );
        }
    };

    confess DBI->errstr unless $dbh;

    my $driver_type = $dbh->{Driver}{Name}
        || (DBI->parse_dsn( $self->{connect_info}[0] ))[1];

    $self->{query} ||= DBIx::ObjectMapper::SQL->new($driver_type);
    $self->{driver_type} = $driver_type;

    $self->{driver} = DBIx::ObjectMapper::Engine::DBI::Driver->new(
        $driver_type,
        $dbh,
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

    if( $self->{connect_do} ) {
        $dbh->do($_) for @{$self->{connect_do}};
    }

    $self->{txn_active} = $dbh->{AutoCommit} ? 0 : 1 ;
    $self->{_dbh_gen}++;

    return $dbh;
}


#### TRANSACTION & SAVEPOINT

sub txn_begin {
    my $self = shift;

    my $dbh = $self->dbh;
    if ( $self->{txn_active} == 0 and $dbh->{AutoCommit} ) {
        eval { $dbh->begin_work };
        if ($@) {
            confess "begin_work failed:" . $@;
        }
        else {
            $self->log->info('BEGIN;');
        }
    }
    elsif ( $self->{txn_active} > 0 ) {
        cluck "Already in transaction";
        return;
    }
    else {
        confess 'AutoCommit is true and txn_active is false.';
    }

    return $self->{txn_active}++;
}

sub txn_commit {
    my $self = shift;
    $self->_txn_end('commit', @_);
}

sub txn_rollback {
    my $self = shift;
    $self->_txn_end('rollback', @_);
}

sub _txn_end {
    my $self = shift;
    my $meth = shift;

    my $dbh = $self->dbh
        or confess "$meth called without a stored handle--begin_work?";

    if( $self->{txn_active} > 0 and !$dbh->{AutoCommit} ) {
        eval { $dbh->$meth() };
        confess "$meth failed for driver $self: $@" if $@;
        $self->log->info(uc($meth) . ';');
        $self->{txn_active} = 0;
    }
    else {
        $self->log->warn('no transaction in progress.');
    }

    return 1;
}

sub txn_do {
    my $self = shift;
    my $code = shift;
    confess "it must be CODE reference" unless ref $code eq 'CODE';

    return $self->svp_do( $code, @_ ) if $self->{txn_active};

    my @res;
    eval {
        $self->txn_begin(@_);
        @res = $code->();
        $self->txn_commit(@_);
    };

    if( my $err = $@ ) {
        $self->txn_rollback(@_);
        confess 'Transaction aborted: ' . $err;
    }

    return wantarray ? @res : $res[0];
}

sub svp_do {
    my $self = shift;
    my $code = shift;
    confess "it must be CODE reference" unless ref $code eq 'CODE';

    ++$self->{_svp_depth};
    my $name = "savepoint_$self->{_svp_depth}";

    my $dbh    = $self->dbh;
    my $driver = $self->driver;
    my @ret;
    eval {
        $self->log->info('SAVEPOINT ' . $name . ';');
        $driver->set_savepoint($dbh, $name);
        @ret = $code->();
        $driver->release_savepoint($dbh, $name);
        $self->log->info('RELEASE SAVEPOINT ' . $name . ';');
    };
    --$self->{_svp_depth};

    if (my $err = $@) {
        $self->log->info('ROLLBACK TO SAVEPOINT ' . $name . ';');
        $driver->rollback_savepoint($self->dbh, $name);
        $driver->release_savepoint($dbh, $name);
        $self->log->info('RELEASE SAVEPOINT ' . $name . ';');
        confess $err;
    }

    return wantarray ? @ret : $ret[0];
}


###################
sub transaction {
    my $self = shift;
    if (@_) {
        my $code = shift;
        confess "it must be CODE reference"
            unless $code and ref $code eq 'CODE';
        return $self->txn_do($code);
    }
    else {
        return DBIx::ObjectMapper::Engine::DBI::Transaction->new($self);
    }
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

sub _prepare {
    my ( $self, $sql ) = @_;
    my $dbh = $self->dbh; # for on_connect_do
    return $self->{disable_prepare_caching}
        ? $dbh->prepare($sql)
        : $dbh->prepare_cached( $sql, undef, 3 );
}

sub select {
    my ( $self, $query, $callback ) = @_;
    my $query_class = ref( $self->query ) . '::Select';
    unless ( ref $query eq $query_class ) {
        $query = $self->_as_query_object( 'select', $query );
    }
    return $self->iterator->new( $query, $self, $callback );
}

sub select_single {
    my ( $self, $query, $callback ) = @_;
    my $query_class = ref( $self->query ) . '::Select';
    unless ( ref $query eq $query_class ) {
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
        #$result = $self->dbh->selectrow_arrayref($sql, +{}, @bind);
        my $sth = $self->_prepare($sql);
        $sth->execute(@bind) || confess $sth->errstr;
        $result = $sth->fetchrow_arrayref;
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

sub _as_query_object {
    my ($self, $action, $query ) = @_;
    return $self->query->$action( %$query );
}

sub update {
    my ( $self, $query, $callback ) = @_;

    my $query_class = ref( $self->query ) . '::Update';
    unless ( ref $query eq $query_class ) {
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
    return $self->dbh->do($sql, {}, @bind);
}

sub insert {
    my ( $self, $query, $callback, $primary_keys ) = @_;

    my $query_class = ref( $self->query ) . '::Insert';
    unless ( ref $query eq $query_class ) {
        $query = $self->_as_query_object('insert', $query);
    }

    $callback->($query) if $callback and ref($callback) eq 'CODE';

    my ( $sql, @bind ) = $query->as_sql;
    $self->stm_debug($sql, @bind);
    $self->dbh->do( $sql, {}, @bind );

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

    my $query_class = ref( $self->query ) . '::Delete';
    unless ( ref $query eq $query_class ) {
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
    return $self->dbh->do( $sql, {}, @bind );
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
