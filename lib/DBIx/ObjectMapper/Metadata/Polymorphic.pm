package DBIx::ObjectMapper::Metadata::Polymorphic;
use strict;
use warnings;
use Carp::Clan qw/^DBIx::ObjectMapper/;
use base qw(DBIx::ObjectMapper::Metadata::Table);

use Params::Validate qw(:all);
use Scalar::Util;
use List::MoreUtils;

sub new {
    my $class = shift;
    my ( $parent, $child ) = @_;

    my $fk;
    if ( my $fk_tmp = $child->get_foreign_key_by_table( $parent ) ) {
        if (    $child->is_unique_keys( @{ $fk_tmp->{keys} } )
            and $parent->is_unique_keys( @{ $fk_tmp->{refs} } ) )
        {
            $fk = $fk_tmp;
        }
    }

    $fk ||= {
        keys  => $child->primary_key,
        refs  => $parent->primary_key,
        table => $child->table_name,
    };

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

    my %column_map;
    for my $i ( 0 .. $#columns ) {
        my $col_name = $columns[$i]->name;
#        if( $column_map{$col_name} ) {
#            confess "column '$col_name' already exists."
#        }
        $column_map{$col_name} = $i + 1;
    }

    my @foreignkeys = ( @{$parent->foreign_key}, @{$child->foreign_key} );
    my @uniquekeys  = ( @{$parent->unique_key}, @{$child->unique_key} );

    my $self = bless {
        table_name  => $parent->table_name,
        metadata    => $parent->metadata,
        columns     => \@columns,
        column_map  => \%column_map,
        engine      => $parent->engine,
        query_class => $parent->{query_class}
            || $class->DEFAULT_QUERY_CLASS(),
        column_metaclass    => $class->DEFAULT_COLUMN_METACLASS,
        primary_key         => $parent->primary_key || [],
        foreign_key         => \@foreignkeys,
        unique_key          => \@uniquekeys,
        polymorphic_columns => \@columns,
        rel_cond            => \@rel_cond,
        rel_key             => $fk,
        parent_table        => $parent,
        child_table         => $child,
        shared_column       => \%shared_column,
    }, $class;

    Scalar::Util::weaken($self->{metadata});
    return $self;
}

sub parent_table { $_[0]->{parent_table} }
sub child_table  { $_[0]->{child_table} }
sub table_name { $_[0]->{table_name} }
sub rel_cond  { $_[0]->{rel_cond} }

sub clone {
    my $self = shift;
    my $alias = shift;
    my $class = ref $self;
    my $clone =  bless { %$self }, $class;
    $clone->parent_table->as($alias);
    return $clone;
}

sub is_clone {
    my $self = shift;
    $self->parent_table->is_clone;
}


=head2 primary_key

=cut

sub primary_key { $_[0]->{primary_key} }

=head2 unique_key

=cut

sub unique_key { $_[0]->{unique_key} }

=head2 foreign_key

=cut

sub foreign_key { $_[0]->{foreign_key} }

sub column {
    my $self = shift;

    if( @_ == 1 and !ref($_[0]) ) {
        my $name = shift;
        if( exists $self->column_map->{$name} ) {
            return $self->{columns}->[ $self->column_map->{$name} - 1 ];
        }
        else {
            return;
        }
    }
    elsif( @_ == 0 ) {
        return @{$self->columns};
    }
    else {
        confess '$obj->column(Scalar|Void)';
    }
}

sub columns    { $_[0]->{columns} }
sub column_map { $_[0]->{column_map} }

sub individual_find {
    my $self = shift;
    my $hashref_data = shift;
    my $uow = shift;

    if( ref($self->parent_table) eq ref($self) ) {
        $hashref_data = $self->parent_table->individual_find(
            $hashref_data, $uow);
    }

    my %rel_cond;
    my $fk = $self->{rel_key};
    for my $i ( 0 .. $#{ $fk->{keys} } ) {
        $rel_cond{ $fk->{keys}->[$i] }
            = $hashref_data->{ $fk->{refs}->[$i] };
    }

    my $child_data = $self->child_table->find(\%rel_cond);
    $uow->{query_cnt}++;
    return { %$hashref_data, %$child_data };
}

sub insert {
    my $self = shift;
    my %data = @_;

    my %parent_data;
    my %child_data;

    for my $key ( keys %data ) {
        if( $self->parent_table->c($key) ) {
            $parent_data{$key} = $data{$key};
        }

        if( $self->child_table->c($key) ) {
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
        else {
            if( $self->parent_table->c($key) ) {
                $parent_data{$key} = $data->{$key};
            }

            if( $self->child_table->c($key) ) {
                $child_data{$key} = $data->{$key};
            }
        }
    }

    my @query;

    if( keys %parent_data ) {
        my @parent_where = $self->cast_cond( 'parent', $cond );
        push @query,
            $self->parent_table->update(\%parent_data, \@parent_where);
    }

    if( keys %child_data ) {
        my @child_where = $self->cast_cond( 'child', $cond );
        push @query, $self->child_table->update(\%child_data, \@child_where);
    }

    return @query;
}

sub delete {
    my $self = shift;
    my @where = @_;

    my @query;

    my @child_where = $self->cast_cond( 'child', \@where );
    push @query, $self->child_table->delete(@child_where);

    my @parent_where = $self->cast_cond( 'parent', \@where );
    push @query,  $self->parent_table->delete(@parent_where);

    return @query;
}

sub select {
    my $self = shift;
    my $parent_join = $self->parent_table->select->builder->join;
    return $self->query_object->select( $self->_select_query_callback )
        ->column( @{ $self->columns } )->from($self->parent_table->table_name)
        ->join( @$parent_join,
        [ $self->child_table => $self->rel_cond => 'INNER' ] );
}

sub _select_query_callback_core {
    my ( $self, $col_obj, $col_name, $result, $row, $i ) = @_;

    my %table = (
        $self->parent_table->table_name => 1,
        $self->child_table->table_name => 1,
    );

    if( my $p_alias = $self->parent_table->alias_name ) {
        $table{$p_alias} = 1;
    }

    if( my $c_alias = $self->child_table->alias_name ) {
        $table{$c_alias} = 1;
    }

    if ( $table{$col_obj->table} ) {
        $result->{ $col_name } = $col_obj->from_storage( $row->[$i] );
    }
    else {
        $result->{ $col_obj->table }->{ $col_name }
            = $col_obj->from_storage( $row->[$i] );
    }
}

sub count {
    my $self = shift;
    return $self->select->count;
}

1;
