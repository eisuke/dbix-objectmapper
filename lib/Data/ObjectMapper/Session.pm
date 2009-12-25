package Data::ObjectMapper::Session;
use strict;
use warnings;
use Carp::Clan;
use Scalar::Util qw(refaddr blessed);
use Data::ObjectMapper::Utils;
use Data::ObjectMapper::Session::Query;
use Data::ObjectMapper::Session::IdentityMap;
use Data::ObjectMapper::Session::UnitOfWork;
my $DEFAULT_QUERY_CLASS = 'Data::ObjectMapper::Session::Query';

sub new {
    my $class = shift;
    my %attr = @_;

    my $cache = $attr{cache} || Data::ObjectMapper::Session::Cache->new();
    my $self = bless {
        query_class => $attr{query_class} || $DEFAULT_QUERY_CLASS,
        queries     => +{},
        autoflush   => $attr{autoflush}   || 1,
        cache       => $cache,
        id_map      => +{},
        unit_of_work => Data::ObjectMapper::Session::UnitOfWork->new($cache),
    }, $class;

    return $self;
}

sub autoflush   { $_[0]->{autoflush}  }
#sub autocommit  { $_[0]->{autocommit} }
sub query_class { $_[0]->{query_class} }
sub uow { $_[0]->{unit_of_work} }

sub query {
    my $self = shift;
    my $t_class = shift;
    $t_class = ref($t_class) if blessed($t_class);
    $self->{queries}{$t_class} ||= $self->query_class->new( $t_class );
    $self->{queries}{$t_class};
}

sub id_map {
    my $self = shift;
    my $t_class = shift;
    $t_class = ref($t_class) if blessed($t_class);
    $self->{id_map}{$t_class} ||= Data::ObjectMapper::Session::IdentityMap->new(
        $t_class, $self->{cache} );
    $self->{id_map}{$t_class};
}

sub load {
    my $self = shift;
    $self->uow->get(@_);
}

sub add {
    my $self = shift;
    my $obj  = shift || return;
    $self->uow->add($obj);
    $self->flush($obj) if $self->autoflush;
}

sub add_all {
    my $self = shift;
    $self->add($_) for @_;
    return scalar(@{$self->{objects}});
}

sub flush {
    my $self = shift;
    my $obj  = shift;
    $self->uow->flush($obj);
}

sub save_or_update {
    my $self = shift;
    my $obj  = shift;

    my $query  = $self->query(ref($obj));
    if( $query->is_persistent($obj) ) {

    }
    elsif( $query->is_detached($obj) ) {
        confess "$obj has detached from this session.";
    }
    else {

    }
}

sub delete {}

# expunge ?
sub detach {
    my $self = shift;
    my $obj  = shift;
    $self->query(ref($obj))->detach($obj);
}

1;
