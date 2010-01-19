package Data::ObjectMapper::Relation;
use strict;
use warnings;
use Carp::Clan qw/^Data::ObjectMapper/;
use Data::ObjectMapper::Session::Array;

my %CASCADE_TYPES = (
    # type         => [ single, multi ]
    save_update    => [ 0, 1 ],
    delete         => [ 0, 1 ],
    detach         => [ 0, 1 ],
    reflesh_expire => [ 0, 1 ],
);

sub new {
    my ( $class, $rel_class, $option ) = @_;

    my $self = bless +{
        name      => undef,
        rel_class => $rel_class,
        option    => $option,
        type      => 'rel',
        cascade   => +{}
    }, $class;

    $self->_init_option;
    return $self;
}

sub _init_option {
    my $self = shift;

    if( my $cascade_option = $self->{option}{cascade} ) {
        $cascade_option =~ s/\s//g;
        my %cascade = map { $_ => 1 } split ',', $cascade_option;
        if( $cascade{all} ) {
            $self->{cascade}{$_} = 1 for keys %CASCADE_TYPES;
        }
        else {
            for my $c ( keys %CASCADE_TYPES ) {
                $self->{cascade}{$c} = 1 if $cascade{$c};
            }
        }
    }


}

{
    no strict 'refs';
    my $pkg = __PACKAGE__;
    for my $cascade ( keys %CASCADE_TYPES ) {
        *{"$pkg\::is_cascade_$cascade"} = sub {
            my $self = shift;
            return $self->{cascade}{$cascade} || do {
                if( $self->is_multi ) {
                    $CASCADE_TYPES{$cascade}->[1];
                }
                else {
                    $CASCADE_TYPES{$cascade}->[0];
                }
            }
        };
    }
};

sub type      { $_[0]->{type} }
sub rel_class { $_[0]->{rel_class} }
sub option    { $_[0]->{option} }
sub mapper    { $_[0]->rel_class->__class_mapper__ }
sub table     { $_[0]->mapper->table }

sub name {
    my $self = shift;
    $self->{name} = shift if @_;
    return $self->{name};
}

sub get_foregin_key {}

sub validation {}

sub get_one_cond {
    my $self = shift;
    my $mapper = shift;
    my $class_mapper = $mapper->instance->__class_mapper__;
    my $rel_mapper = $self->mapper;

    my $fk = $self->foreign_key($class_mapper->table, $rel_mapper->table);
    my @cond;
    for my $i ( 0 .. $#{$fk->{keys}} ) {
        push @cond,
            $rel_mapper->table->c( $fk->{refs}->[$i] )
                == $mapper->instance->{$fk->{keys}->[$i]};
    }

    return @cond;
}

sub get_multi_cond {
    my $self = shift;
    my $mapper = shift;
    my $class_mapper = $mapper->instance->__class_mapper__;
    my $rel_mapper = $self->mapper;
    my $fk = $self->foreign_key($class_mapper->table, $rel_mapper->table);

    my @cond;
    for my $i ( 0 .. $#{$fk->{keys}} ) {
        push @cond,
            $rel_mapper->table->c( $fk->{keys}->[$i] )
                == $mapper->instance->{$fk->{refs}->[$i]};
    }

    return @cond;
}

sub get_one {
    my $self = shift;
    my $name = shift;
    my $mapper = shift;
    my @cond = $self->get_one_cond($mapper);
    return if @cond == 1 and !defined $cond[0]->[2];
    $mapper->instance->{$name} = $mapper->unit_of_work->get(
        $self->rel_class => \@cond
    );
}

sub get_multi {
    my $self = shift;
    my $name = shift;
    my $mapper = shift;
    my @cond = $self->get_multi_cond($mapper);

    my $rel_mapper = $self->mapper;
    my @new_val
        = $mapper->unit_of_work->query( $self->rel_class )->where(@cond)
        ->order_by( map { $rel_mapper->table->c($_) }
            @{ $rel_mapper->table->primary_key } )->execute->all;

    $mapper->instance->{$name} = Data::ObjectMapper::Session::Array->new(
        $mapper->unit_of_work,
        @new_val
    );
}


sub is_multi { 0 }

sub relation_condition {}

sub mapping {
    my $self = shift;
    my $data = shift;
    return $self->mapper->mapping($data);
}

sub is_self_reference {
    my $self = shift;
    my $refs_table = shift;
    return $refs_table eq $self->table;
}

sub cascade_delete {
    my $self = shift;
    my $mapper = shift;

    return unless $self->is_cascade_delete;

    my @cond;
    if( $self->is_multi ) {
        @cond = $self->get_multi_cond($mapper);
    }
    else {
        @cond = $self->get_one_cond($mapper);
    }

    return if !@cond || ( @cond == 1 and !defined $cond[0]->[2] );
    $self->table->delete->where(@cond)->execute;
}

1;
