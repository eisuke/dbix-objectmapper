package Data::ObjectMapper::Engine::DBI::Transaction;
use strict;
use warnings;
use Carp::Clan;

sub new {
    my ( $class, $dbh, $driver ) = @_;

    my $self = bless {
        dbh      => $dbh,
        driver   => $driver,
        complete => 0,
    }, $class;

    $self->begin;
    return $self;
}

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
        warn 'BEGIN;';    # XXXX
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
            warn uc($meth) . ';';
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

