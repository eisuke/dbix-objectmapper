package DBIx::ObjectMapper::Relation::HasOne;
use strict;
use warnings;
use base qw(DBIx::ObjectMapper::Relation);

sub initial_is_multi { 0 }

sub get {
    my $self = shift;
    $self->get_one(@_);
}

sub foreign_key {
    my ( $self, $my_table, $ref_table ) = @_;

    return {
        keys  => $my_table->primary_key,
        refs  => $ref_table->primary_key,
        table => $ref_table->table_name,
    };
}

sub relation_condition {
    my $self = shift;
    my $class_table = shift;
    my $table = shift;

    my $fk = $self->foreign_key($class_table, $table);

    my @cond;
    for my $i ( 0 .. $#{$fk->{keys}} ) {
        push @cond,
            $table->c( $fk->{keys}->[$i] )
                == $class_table->c($fk->{refs}->[$i]);
    }

    return @cond;
}

1;
