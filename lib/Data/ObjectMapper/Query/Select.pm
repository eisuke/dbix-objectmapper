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
    for my $meth ( qw( column from where join order_by
                       group_by limit offset having
                       add_column add_where add_join
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
    return $self->engine->select( $self->builder, $self->callback, @_ );
}

sub as_metadata {
    my $self = shift;

}

1;
