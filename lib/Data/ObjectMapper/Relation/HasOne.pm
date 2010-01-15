package Data::ObjectMapper::Relation::HasOne;
use strict;
use warnings;
use base qw(Data::ObjectMapper::Relation);

sub get {
    my $self = shift;
    $self->get_one(@_);
}

sub foreign_key {
    my ( $self, $class_table, $table ) = @_;
    return {
        keys  => $table->primary_key,
        refs  => $class_table->primary_key,
        table => $class_table->table_name,
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
