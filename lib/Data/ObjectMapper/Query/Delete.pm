package Data::ObjectMapper::Query::Delete;
use strict;
use warnings;
use base qw(Data::ObjectMapper::Query);

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->builder( $self->engine->query->delete );
    return $self;
}

{
    no strict 'refs';
    my $pkg = __PACKAGE__;
    for my $meth ( qw( table where add_table add_where ) ) {
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
    return $self->engine->delete( $self->builder, $callback );
}

1;

