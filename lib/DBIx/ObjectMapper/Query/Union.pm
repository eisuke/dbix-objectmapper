package DBIx::ObjectMapper::Query::Union;
use strict;
use warnings;
use Carp::Clan qw/^DBIx::ObjectMapper/;
use Data::Page;
use base qw(DBIx::ObjectMapper::Query::Base);

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->builder( $self->engine->query->union );
    return $self;
}

{
    no strict 'refs';
    my $pkg = __PACKAGE__;
    for my $meth ( qw( order_by group_by
                       having
                       limit offset
                       add_order_by add_group_by
                       add_having
                       sets add_sets ) ) {
        *{"$pkg\::$meth"} = sub {
            my $self = shift;
            $self->builder->$meth(@_);
            return $self;
        };
    }
};


sub pager {
    my $self = shift;
    my $page = shift || 1;
    confess 'page must be integer.' unless $page =~ /^\d+$/ and $page > 0;

    my $limit = $self->builder->limit->[0] || confess "limit is not set.";
    $self->offset( ( $page - 1 ) * $limit );

    my $pager = Data::Page->new();
    $pager->total_entries( $self->count );
    $pager->entries_per_page( $self->builder->{limit}->[0] || 0 );
    $pager->current_page( $page );
    return $pager;
}

sub execute {
    my $self = shift;
    return $self->engine->union( $self->builder, $self->callback, @_ );
}

sub as_sql {
    my $self = shift;
    return $self->builder->as_sql(@_);
}

1;
