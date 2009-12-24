package Data::ObjectMapper::Query::Insert;
use strict;
use warnings;
use base qw(Data::ObjectMapper::Query);

sub new {
    my $class = shift;
    my $engine = shift;
    my $callback = shift;
    my $self = $class->SUPER::new($engine, $callback);
    $self->{primary_keys} = shift || [];
    $self->builder( $self->engine->query->insert );
    return $self;
}

{
    no strict 'refs';
    my $pkg = __PACKAGE__;
    for my $meth ( qw( table values add_table add_values ) ) {
        *{"$pkg\::$meth"} = sub {
            my $self = shift;
            $self->builder->$meth(@_);
            return $self;
        };
    }
};

sub execute {
    my $self = shift;
    return $self->engine->insert( $self->builder, $self->callback, $self->{primary_keys} );
}

1;

