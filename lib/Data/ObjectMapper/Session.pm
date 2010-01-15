package Data::ObjectMapper::Session;
use strict;
use warnings;
use Carp::Clan;
use Scalar::Util qw(refaddr blessed);
use Data::ObjectMapper::Utils;
use Data::ObjectMapper::Session::Cache;
use Data::ObjectMapper::Session::Query;
use Data::ObjectMapper::Session::UnitOfWork;
my $DEFAULT_QUERY_CLASS = 'Data::ObjectMapper::Session::Query';

sub new {
    my $class = shift;
    my %attr = @_;

    my $cache = $attr{cache} || Data::ObjectMapper::Session::Cache->new();
    my $query_class = $attr{query_class} || $DEFAULT_QUERY_CLASS;

    my $self = bless {
        engine => $attr{engine} || undef,
        autoflush  => exists $attr{autoflush}  ? $attr{autoflush}  : 0,
        autocommit => exists $attr{autocommit} ? $attr{autocommit} : 1,
        cache      => $cache,
        unit_of_work => Data::ObjectMapper::Session::UnitOfWork->new(
            $cache, $query_class
        ),
        transaction => undef,
    }, $class;
    $self->{transaction} = $attr{engine}->transaction
        unless $self->autocommit;

    return $self;
}

sub autoflush   { $_[0]->{autoflush} }
sub autocommit  { $_[0]->{autocommit} }
sub uow         { $_[0]->{unit_of_work} }

sub query {
    my $self = shift;
    return $self->uow->query(@_);
}

sub get {
    my $self = shift;
    $self->uow->get(@_);
}

sub add {
    my $self = shift;
    my $obj  = shift || return;
    $self->uow->add($obj);
    $self->flush() if $self->autoflush;
    return $obj;
}

sub add_all {
    my $self = shift;
    $self->add($_) for @_;
    return @_;
}

sub flush {
    my $self = shift;
    $self->uow->flush();
}

sub delete {
    my $self = shift;
    my $obj  = shift;
    $self->uow->delete($obj);
    $self->flush() if $self->autoflush;
    return $obj;
}

sub commit {
    my $self = shift;
    $self->flush;
    $self->{transaction}->commit unless $self->autocommit;
}

sub rollback {
    my $self = shift;

    cluck "Can't rollback. autocommit is true this session."
        if $self->autocommit;
    $self->{transaction}->rollback;
}

sub txn {
    my $self = shift;
    my $code = shift;
    confess "it must be CODE reference" unless $code and ref $code eq 'CODE';
    return $self->{engine}->transaction( $code, @_ );
}

sub detach {
    my $self = shift;
    my $obj  = shift;
    $self->uow->detach($obj);
}

sub DESTROY {
    my $self = shift;
    $self->rollback unless $self->autocommit;
    $self->uow->demolish; ## dissolve cycle reference
}

1;
