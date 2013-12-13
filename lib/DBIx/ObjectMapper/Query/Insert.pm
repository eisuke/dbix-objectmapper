package DBIx::ObjectMapper::Query::Insert;
use strict;
use warnings;
use base qw(DBIx::ObjectMapper::Query::Base);

sub new {
    my $class    = shift;
    my $self = $class->SUPER::new( @_ );
    my $engine   = shift;
    my $callback = shift;
    my $before = shift;
    my $after = shift;
    $self->{primary_keys} = shift || [];
    $self->builder( $self->engine->query->insert );
    return $self;
}

{
    no strict 'refs';
    my $pkg = __PACKAGE__;
    for my $meth ( qw( into values add_values ) ) {
        *{"$pkg\::$meth"} = sub {
            my $self = shift;
            $self->builder->$meth(@_);
            return $self;
        };
    }
};

sub execute {
    my $self = shift;
    my $primary_key
        = @{ $self->{primary_keys} } ? $self->{primary_keys} : shift || undef;
    $self->{before}
        ->( $self->metadata, $self->builder, $self->builder->{into}->[0] );
    my $res = $self->engine->insert( $self->builder, $self->callback,
        $primary_key );
    $self->{after}->( $self->metadata, $res, $self->builder->{into}->[0], $self->builder );
    return $res;
}

1;
