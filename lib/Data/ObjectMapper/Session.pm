package Data::ObjectMapper::Session;
use strict;
use warnings;
use Carp::Clan;

sub new {
    my $class = shift;
    bless {
        id_map => +{},
        unit_of_work => +{},
    }, $class;
}

sub query {

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

    my %result;
    for my $attr ( keys %{$self->attributes_config} ) {
        my $getter = $self->attributes_config->{$attr}{getter};
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

}

1;
