package DBIx::ObjectMapper::Metadata::Polymorphic;
use strict;
use warnings;
use Carp::Clan qw/^DBIx::ObjectMapper/;
use base qw(DBIx::ObjectMapper::Metadata::Query);

use Params::Validate qw(:all);
use Scalar::Util;
use List::MoreUtils;

sub new {
    my $class = shift;
    my ( $parent, $child ) = @_;

    # XXX NATURAL JOIN ?
    my $fk;
    if ( my $fk_tmp = $child->get_foreign_key_by_table( $parent ) ) {
        $fk = $fk_tmp;
    }
    else {
        $fk = {
            keys  => $child->primary_key,
            refs  => $parent->primary_key,
            table => $child->table_name,
        };
    }

    my %shared_column;
    my @rel_cond;
    for my $i ( 0 .. $#{$fk->{keys}} ) {
        push @rel_cond,
            $child->c( $fk->{keys}->[$i] ) == $parent->c( $fk->{refs}->[$i] );
        $shared_column{$fk->{keys}->[$i]} = $fk->{refs}->[$i];
    }

    my @columns = (
        @{$parent->columns},
        grep{ !exists $shared_column{$_->name } } @{$child->columns},
    );

    my $self = $class->SUPER::new(
        $parent->table_name . '_' . $child->table_name,
        $parent->select->column(@columns)->join([ $child => \@rel_cond ]),
        {
            primary_key => $parent->primary_key,
            unique_key  => $parent->unique_key,
        }
    );

    $self->{polymorphic_columns} = \@columns;
    $self->{rel_cond} = \@rel_cond;
    $self->{parent_table} = $parent;
    $self->{child_table}  = $child;
    $self->{shared_column} = \%shared_column;

    return $self;
}

sub parent_table { $_[0]->{parent_table} }
sub child_table  { $_[0]->{child_table} }

sub insert {
    my $self = shift;
    my %data = @_;

    my %parent_data;
    my %child_data;

    for my $key ( keys %data ) {
        if( $self->parent_table->c($key) ) {
            $parent_data{$key} = $data{$key};
        }
        elsif( $self->child_table->c($key) ) {
            $child_data{$key} = $data{$key};
        }
    }

    my $parent_data = $self->parent_table->insert(%parent_data)->execute;
    for my $add_col( keys %{$self->{shared_column}} ) {
        $child_data{$add_col} = $parent_data->{$self->{shared_column}{$add_col}}
            if exists $parent_data->{$self->{shared_column}{$add_col}};
    }

    return $self->child_table->insert(%child_data);
}

sub cast_cond {
    my ( $self, $type, $cond ) = @_;

    my @cond;
    my $table = $type eq 'parent' ? $self->parent_table : $self->child_table;
    for my $c (@$cond) {
        push @cond, [ map { ref $_ ? $table->c( $_->name ) : $_ } @$c ];
    }

    return @cond;
}

sub update {
    my $self = shift;
    my ( $data, $cond ) = @_;

    my %parent_data;
    my %child_data;
    for my $key ( keys %$data ) {
        if( $self->{shared_column}->{$key} ) {
            $parent_data{$key} = $data->{$key};
            $child_data{$key} = $data->{$key};
        }
        elsif( $self->parent_table->c($key) ) {
            $parent_data{$key} = $data->{$key};
        }
        elsif( $self->child_table->c($key) ) {
            $child_data{$key} = $data->{$key};
        }
    }

    my @query;

    if( keys %parent_data ) {
        my @parent_where = $self->cast_cond( 'parent', $cond );
        push @query,
            $self->parent_table->update->set(%parent_data)
            ->where(@parent_where);
    }

    if( keys %child_data ) {
        my @child_where = $self->cast_cond( 'child', $cond );
        push @query,
            $self->child_table->update->set(%child_data)->where(@child_where);
    }

    return @query;
}

sub delete {
    my $self = shift;
    my @where = @_;

    my @query;

    my @parent_where = $self->cast_cond( 'parent', \@where );
    push @query,  $self->parent_table->delete(@parent_where);

    my @child_where = $self->cast_cond( 'child', \@where );
    push @query, $self->child_table->delete(@child_where);

    return @query;
}

1;
