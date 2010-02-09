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

    if( my $fk = $ref_table->get_foreign_key_by_table( $my_table ) ) {
        return $fk;
    }
    else {
        return {
            keys  => $ref_table->primary_key,
            refs  => $my_table->primary_key,
            table => $ref_table->table_name,
        };
    }
}

sub identity_condition {
    my $self = shift;
    my $mapper = shift;
    my $class_mapper = $mapper->instance->__class_mapper__;
    my $rel_mapper = $self->mapper;

    my $fk = $self->foreign_key($class_mapper->table, $rel_mapper->table);

    my @cond;
    for my $i ( 0 .. $#{$fk->{keys}} ) {
        my $val = $mapper->get_val($fk->{refs}->[$i]);
        next unless defined $val;
        push @cond, $rel_mapper->table->c( $fk->{keys}->[$i] ) == $val;
    }
    return @cond;
}

sub relation_condition {
    my $self = shift;
    my $class_table = shift;
    my $table = shift;

    my $fk = $self->foreign_key($class_table, $table);

    my @cond;
    for my $i ( 0 .. $#{$fk->{keys}} ) {
        push @cond,
            $class_table->c( $fk->{keys}->[$i] )
                == $table->c($fk->{refs}->[$i]);
    }

    return @cond;
}

1;
