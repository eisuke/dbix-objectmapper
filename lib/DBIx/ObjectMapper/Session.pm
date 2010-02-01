package DBIx::ObjectMapper::Session;
use strict;
use warnings;
use Carp::Clan;
use Params::Validate qw(:all);
use Scalar::Util qw(refaddr blessed);
use DBIx::ObjectMapper::Utils;
use DBIx::ObjectMapper::Session::Cache;
use DBIx::ObjectMapper::Session::Query;
use DBIx::ObjectMapper::Session::UnitOfWork;
my $DEFAULT_QUERY_CLASS = 'DBIx::ObjectMapper::Session::Query';

sub new {
    my $class = shift;

    my %attr = validate(
        @_,
        {   engine => { type => OBJECT, isa => 'DBIx::ObjectMapper::Engine' },
            autocommit   => { type => BOOLEAN, default => 1 },
            autoflush    => { type => BOOLEAN, default => 0 },
            share_object => { type => BOOLEAN, default => 0 },
            no_cache     => { type => BOOLEAN, default => 0 },
            cache        => {
                type      => OBJECT,
                callbacks => {
                    'ducktype' => sub {
                        ( grep { $_[0]->can($_) } qw(get set remove clear) )
                            == 4;
                        }
                },
                default => DBIx::ObjectMapper::Session::Cache->new()
            },
            query_class =>
                { type => SCALAR, default => $DEFAULT_QUERY_CLASS },

        }
    );

    $attr{transaction}
        = $attr{autocommit} ? undef : $attr{engine}->transaction;
    $attr{unit_of_work}
        = DBIx::ObjectMapper::Session::UnitOfWork->new(
        ( $attr{no_cache} ? undef : $attr{cache} ),
        $attr{query_class},
        { share_object => $attr{share_object} },
    );

    return bless \%attr, $class;
}

sub autoflush   { $_[0]->{autoflush} }
sub autocommit  { $_[0]->{autocommit} }
sub uow         { $_[0]->{unit_of_work} }

sub query {
    my $self = shift;
    $self->flush;
    return $self->uow->query(@_);
}

sub get {
    my $self = shift;
    $self->flush;
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
    unless( $self->autocommit ) {
        $self->{transaction}->commit;
        $self->{transaction} = $self->{engine}->transaction;
    }
}

sub rollback {
    my $self = shift;

    cluck "Can't rollback. autocommit is TRUE this session."
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
    $self->uow->demolish; ## dissolve cycle reference
    $self->{unit_of_work} = undef;
    $self->rollback unless $self->autocommit;
    warn "DESTROY $self" if $ENV{MAPPER_DEBUG};
}

1;
