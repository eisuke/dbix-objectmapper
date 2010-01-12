package Data::ObjectMapper::Relation::BelongsTo;
use strict;
use warnings;
use base qw(Data::ObjectMapper::Relation);

sub get {
    my $self = shift;
    $self->get_one(@_);
}

sub relation_condition {
    my $self = shift;
    my $class_mapper = shift;
    my $table = shift;
    my $rel_mapper = $self->mapper;

    my $fk = $class_mapper->table->get_foreign_key_by_table(
        $rel_mapper->table
    );

    my @cond;
    for my $i ( 0 .. $#{$fk->{keys}} ) {
        push @cond,
            $table->c( $fk->{refs}->[$i] )
                == $class_mapper->table->c($fk->{keys}->[$i]);
    }

    return @cond;
}

1;
