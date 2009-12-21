package Data::ObjectMapper::Session::Query;
use strict;
use warnings;

sub new {
    my ( $class, $session, $target_class, $option ) = @_;
    bless {
        target_class => $target_class,
        session      => $session,
        option       => $option,
    }, $class;
}

sub target_class { $_[0]->{target_class} }
sub session      { $_[0]->{session} }

sub all {

}

sub find {
    my $self = shift;
    my $id = shift;

    my $mapper = $self->target_class->__mapper__;
    my $result = $mapper->table->find($id) || return;

    my $constructor = $mapper->constructor_config->{name};
    my $type = $mapper->constructor_config->{type};

    ## XXX TODO
    ## unit_of_work
    ## eager loding
    ## lazy loading
    ## ......

    my %param;
    for my $attr ( keys %{$mapper->attributes_config} ) {
        my $isa = $mapper->attributes_config->{$attr}{isa};
        $param{$attr} = $result->{$isa->name};
    }

    return $self->target_class->${constructor}(%param);
}

1;
