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
    my $class_table = shift;
    my $table = shift;
    my $rel_table = $self->mapper->table;

    my $fk = $class_table->get_foreign_key_by_table( $rel_table );

    my @cond;
    for my $i ( 0 .. $#{$fk->{keys}} ) {
        push @cond,
            $table->c( $fk->{refs}->[$i] )
                == $class_table->c($fk->{keys}->[$i]);
    }

    return @cond;
}

1;
