package Data::ObjectMapper::Relation::ManyToMany;
use strict;
use warnings;
use base qw(Data::ObjectMapper::Relation);

sub initial_is_multi { 1 }

sub new {
    my ( $class, $assc_table, $rel_class, $option ) = @_;
    my $self = $class->SUPER::new($rel_class, $option);
    $self->{assc_table} = $assc_table;
    return $self;
}

sub type       {'many_to_many'}
sub assc_table { $_[0]->{assc_table} }

sub identity_condition {
    my $self = shift;
    my $mapper = shift;
    my $class_mapper = $mapper->instance->__class_mapper__;

    my $fk =
        $self->assc_table->get_foreign_key_by_table( $class_mapper->table );
    my @cond;
    for my $i ( 0 .. $#{$fk->{keys}} ) {
        my $val = $mapper->instance->{$fk->{refs}->[$i]};
        next unless defined $val;
        push @cond, $self->assc_table->c( $fk->{keys}->[$i] ) == $val;
    }

    return @cond;
}

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

    my $cond = $mapper->relation_condition->{$name};
    my @val = $mapper->unit_of_work->query( $self->rel_class )
        ->join(
            [ $self->assc_table => \@assc_cond ],
        )
        ->where(@$cond)
        ->order_by( map { $rel_mapper->table->c($_) }
            @{ $rel_mapper->table->primary_key } )->execute->all;

    $mapper->instance->{$name} = Data::ObjectMapper::Session::Array->new(
        $name,
        $mapper,
        @val
    );
}

sub cascade_save {
    my $self = shift;
    my $name = shift;
    my $mapper = shift;
    my $instance = shift;

    my $class_mapper = $mapper->instance->__class_mapper__;
    my $rel_mapper = $self->mapper;

    $mapper->unit_of_work->add($instance);
    $instance->__mapper__->save;

    my %values;
    my $fk1 =
        $self->assc_table->get_foreign_key_by_table( $rel_mapper->table );
    for my $i ( 0 .. $#{$fk1->{keys}} ) {
        $values{ $fk1->{keys}->[$i] } = $instance->{$fk1->{refs}->[$i]};
    }

    my $fk2 =
        $self->assc_table->get_foreign_key_by_table( $class_mapper->table );
    for my $i ( 0 .. $#{$fk2->{keys}} ) {
        $values{ $fk2->{keys}->[$i] }
            = $mapper->instance->{ $fk2->{refs}->[$i] };
    }

    $self->assc_table->insert->values(\%values)->execute;

    return $instance;
}

sub cascade_update {
    my $self = shift;
    my $name = shift;
    my $mapper = shift;

    return unless $self->is_cascade_save_update and $mapper->is_modified;

    my $uniq_cond = $mapper->relation_condition->{$name};
    my $modified_data = $mapper->modified_data;
    my $class_mapper = $mapper->instance->__class_mapper__;

    my %sets;
    my $fk =
        $self->assc_table->get_foreign_key_by_table( $class_mapper->table );
    for my $i ( 0 .. $#{$fk->{keys}} ) {
        $sets{ $fk->{keys}->[$i] } = $modified_data->{ $fk->{refs}->[$i] }
            if $modified_data->{ $fk->{refs}->[$i] };
    }
    return unless keys %sets;
    $self->assc_table->update->set(%sets)->where(@$uniq_cond)->execute;
}

sub cascade_delete {
    my $self = shift;
    my $mapper = shift;

    return unless $self->is_cascade_delete;

    my @cond = $self->identity_condition($mapper);
    return if !@cond || ( @cond == 1 and !defined $cond[0]->[2] );
    $self->assc_table->delete->where(@cond)->execute;
}

sub many_to_many_add {
    my $self = shift;
    my ($name, $mapper, $instance) = @_;
    $self->cascade_save(@_);
}

sub many_to_many_remove {
    my $self = shift;
    my ($name, $mapper, $instance) = @_;
    my $rel_mapper = $self->mapper;
    my $uniq_cond = $mapper->relation_condition->{$name};
    my @cond = @$uniq_cond;

    my $fk1 =
        $self->assc_table->get_foreign_key_by_table( $rel_mapper->table );
    for my $i ( 0 .. $#{$fk1->{keys}} ) {
        push @cond,
            $self->assc_table->c( $fk1->{keys}->[$i] )
                == $instance->{$fk1->{refs}->[$i]};
    }

    $self->assc_table->delete->where(@cond)->execute;
}

1;
