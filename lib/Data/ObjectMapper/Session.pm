package Data::ObjectMapper::Session;
use strict;
use warnings;
use Carp::Clan;
use Scalar::Util;

use Data::ObjectMapper::Session::Query;
my $DEFAULT_QUERY_CLASS = 'Data::ObjectMapper::Session::Query';

sub new {
    my $class = shift;
    my %attr = @_;

    bless {
        unit_of_work => +{},
        query_class => $attr{query_class} || $DEFAULT_QUERY_CLASS,
    }, $class;
}

sub query_class { $_[0]->{query_class} }

sub query {
    my $self = shift;
    $self->query_class->new( $self, @_ );
}

sub add {

}

sub add_all {

}

sub is_modified {

}

sub refresh {

}

sub save {
    my $self = shift;
    my $obj  = shift;

    my $mapper = $obj->__mapper__;

    my %result;
    for my $attr ( keys %{$mapper->attributes_config} ) {
        my $getter = $mapper->attributes_config->{$attr}{getter};
        if( !ref $getter ) {
            $result{$attr} = $obj->$getter;
        }
        elsif( ref $getter eq 'CODE' ) {
            $result{$attr} = $getter->($obj);
        }
        else {
            confess "invalid getter config.";
        }
    }

    if( $self->unit->persistent($obj) ) {
        $mapper->from->update->set(%result)->execute();
    }
    else {
        $mapper->from->insert->valuse(%result)->execute();
    }

}

1;
