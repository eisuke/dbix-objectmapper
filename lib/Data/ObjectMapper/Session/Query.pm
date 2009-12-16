package Data::ObjectMapper::Session::Query;
use strict;
use warnings;

sub new {
    my ( $class, $mapped_class ) = @_;

}

sub all {

}

sub find {
    my $self = shift;
    my $id = shift;
    my $result = $self->table->find($id) || return;

    my $constructor = $self->constructor_config->{name};
    my $type = $self->constructor_config->{type};

    ## XXX TODO
    ## unit_of_work
    ## eager loding
    ## lazy loading
    ## ......

    my %param;
    for my $attr ( keys %{$self->attributes_config} ) {
        my $isa = $self->attributes_config->{$attr}{isa};
        $param{$attr} = $result->{$isa->name};
    }

    return $self->mapped_class->${constructor}(%param);
}

1;
