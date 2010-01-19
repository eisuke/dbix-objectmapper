package Data::ObjectMapper::Relation::ManyToMany;
use strict;
use warnings;
use base qw(Data::ObjectMapper::Relation);

sub new {
    my ( $class, $assc_table, $rel_class, $option ) = @_;
    my $self = $class->SUPER::new($rel_class, $option);
    $self->{assc_table} = $assc_table;
    return $self;
}

sub assc_table { $_[0]->{assc_table} }

sub get {
    my $self = shift;
    my $name = shift;
    my $mapper = shift;

    my $class_mapper = $mapper->instance->__class_mapper__;
    my $rel_mapper = $self->mapper;

    my $fk1 =
        $self->assc_table->get_foreign_key_by_table( $rel_mapper->table );
    my @assc_cond;
    for my $i ( 0 .. $#{$fk1->{keys}} ) {
        push @assc_cond,
            $self->assc_table->c( $fk1->{keys}->[$i] )
                == $rel_mapper->table->c($fk1->{refs}->[$i]);
    }

    my @cond;
    my $fk2 =
        $self->assc_table->get_foreign_key_by_table( $class_mapper->table );
    for my $i ( 0 .. $#{$fk2->{keys}} ) {
        push @cond,
            $self->assc_table->c( $fk2->{keys}->[$i] )
                == $mapper->instance->{$fk2->{refs}->[$i]}
    }

    my @val = $mapper->unit_of_work->query( $self->rel_class )
        ->join(
            [ $self->assc_table => \@assc_cond ],
        )
        ->where(@cond)
        ->order_by( map { $rel_mapper->table->c($_) }
            @{ $rel_mapper->table->primary_key } )->execute->all;

    $mapper->instance->{$name} = Data::ObjectMapper::Session::Array->new(
        $mapper->unit_of_work,
        @val
    );
}

sub is_multi { 1 }

1;
