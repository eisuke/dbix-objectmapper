package Data::ObjectMapper::Query::Select;
use strict;
use warnings;
use base qw(Data::ObjectMapper::Query);

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->builder( $self->engine->query->select );
    return $self;
}

{
    no strict 'refs';
    my $pkg = __PACKAGE__;
    for my $meth ( qw( column from where joins order_by
                       group_by limit offset having
                       add_column add_where add_joins
                       add_order_by add_group_by add_having ) ) {
        *{"$pkg\::$meth"} = sub {
            my $self = shift;
            $self->builder->$meth(@_);
            return $self;
        };
    }
};

sub execute {
    my $self = shift;
    my $callback = shift || $self->callback;
    return $self->engine->select( $self->builder, $callback );
}

1;
