package Data::ObjectMapper::Engine::DBI::Transaction;
use strict;
use warnings;
use Carp::Clan;

sub new {
    my ( $class, $dbh, $driver, $log ) = @_;

    my $self = bless {
        dbh      => $dbh,
        driver   => $driver,
        log      => $log,
        complete => 0,
    }, $class;

    $self->begin;
    return $self;
}

sub log    { $_[0]->{log} }
sub dbh    { $_[0]->{dbh} }
sub driver { $_[0]->{driver} }

sub begin {
    my $self = shift;
    my $dbh  = $self->dbh;
    eval { $self->driver->begin_work($dbh) };
    if ($@) {
        confess "begin_work failed:" . $@;
    }
    else {
        $self->log->info('BEGIN;');
    }
    return $self;
}

sub commit {
    my $self = shift;
    $self->_txn_end( 'commit', @_ );
}

sub rollback {
    my $self = shift;
    $self->_txn_end( 'rollback', @_ );
}

sub _txn_end {
    my $self = shift;
    my $meth = shift;

    my $dbh    = $self->dbh;
    my $driver = $self->driver;
    if ( !$dbh->{AutoCommit} ) {
        eval { $driver->$meth($dbh) };
        if ($@) {
            confess "$meth failed for driver $self: $@";
        }
        else {
            $self->log->info( uc($meth) . ';' );
            return $self->{complete} = 1;
        }
    }

    return;
}

sub DESTROY {
    my $self = shift;
    return if $self->{complete};
    $self->rollback;
}

1;

