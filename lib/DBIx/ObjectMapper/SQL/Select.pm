package DBIx::ObjectMapper::SQL::Select;
use strict;
use warnings;
use base qw(DBIx::ObjectMapper::SQL::Base);

__PACKAGE__->initdata({
    column   => [],
    from     => [],
    where    => [],
    join     => [],
    order_by => [],
    group_by => [],
    limit    => 0,
    offset   => 0,
    having   => [],
    driver   => '', # Pg, mysql, SQLite ...
});

__PACKAGE__->accessors({
    convert_columns_to_sql => [qw(column order_by group_by)],
    convert_tables_to_sql  => [qw(from)],
    convert_joins_to_sql   => [qw(join)],
    build_where            => [qw(where having)],
    num_check              => [qw(limit offset)],
});

sub _generate_subquery {
    my $self = shift;

    my @bind;
    my ($from, @from_bind) = $self->from_as_sql;
    my ($col, @col_bind) = $self->column_as_sql;

    my $stm = 'SELECT ' . ($col || '*') . ' FROM ' . $from;
    push @bind, @col_bind if @col_bind;
    push @bind, @from_bind if @from_bind;

    my ($join_stm, @join_bind) = $self->join_as_sql;
    $stm .= ' ' . $join_stm if $join_stm;
    push @bind, @join_bind if @join_bind;

    my ($where_stm, @where_bind) = $self->where_as_sql;
    $stm .= ' WHERE ' . $where_stm if $where_stm;
    push @bind, @where_bind if @where_bind;

    my ($group_by, @group_binds) = $self->group_by_as_sql;
    $stm .= ' GROUP BY ' . $group_by if $group_by;
    push @bind, @group_binds if @group_binds;

    my ($having_stm, @having_bind) = $self->having_as_sql;
    $stm .= ' HAVING ' . $having_stm if $having_stm;
    push @bind, @having_bind if @having_bind;

    my ($order_by, @order_binds) = $self->order_by_as_sql;
    $stm .= ' ORDER BY ' . $order_by if $order_by;
    push @bind, @order_binds if @order_binds;

    return ($stm, @bind);
}

sub _final_column_name {
    my ($class, $raw_column) = @_;

    if (!ref $raw_column || ref $raw_column eq 'HASH') {
        return $class->convert_func_to_sql( $raw_column );
    }

    if (defined($raw_column->[1])) {
        return $raw_column->[1];
    }

    my ($column) = $class->convert_func_to_sql( $raw_column->[0] );
    return $column;
}

sub _apply_oracle_limits {
    my ($self, $original_stm, @bind) = @_;

    my $lower_limit = $self->offset ? $self->offset_as_sql : 1;
    return ($original_stm, @bind) if !$lower_limit;
    my $upper_limit = $self->limit  ? $self->limit_as_sql + $lower_limit - 1 : undef;

    my $final_column_list = join(', ', map {$self->_final_column_name($_)} @{$self->column});
    my $stm = "SELECT $final_column_list FROM ( " .
                   "SELECT /*+ first_row */ rownum AS oracle_rownum_XYZZY, $final_column_list FROM ( $original_stm ) " .
              ") WHERE oracle_rownum_XYZZY >= $lower_limit" .
                    (defined($upper_limit) ? " AND oracle_rownum_XYZZY <= $upper_limit" : "");

    return ($stm, @bind);
}

sub _apply_limit_syntax {
    my ($self, $stm, @bind) = @_;

    my $method = $self->limit_syntax->{ lc( $self->{driver} ) };
    $method = $self->limit_syntax->{default}
        unless $method and $self->can($method);
    if( my $add_stm = $self->${method}() ) {
        $stm .= $add_stm;
    }

    return ($stm, @bind);
}

sub as_sql {
    my $self = shift;
    my $mode = shift;

    my ($stm, @bind) = $self->_generate_subquery();

    if( $self->limit || $self->offset ) {
        ($stm, @bind) = $self->{driver} eq 'Oracle' ? $self->_apply_oracle_limits($stm, @bind) :
                                                      $self->_apply_limit_syntax($stm, @bind);
    }

    if( $mode and $mode eq 'parts' ) {
        $stm = '( ' . $stm . ' )';
    }

    return wantarray ? ($stm, @bind) : $stm;
}

sub _add_joins_with_param {
    my $self = shift;
    my $param = shift;
    my @join_params = @_;
    my @real_join_expressions = ();
    while (@join_params) {
        my $table = shift @join_params;
        my $conditions = shift @join_params;
        push @real_join_expressions, [$table, $conditions, $param];
    }
    return $self->add_join(@real_join_expressions);
}

sub add_inner_join {
    my $self = shift;
    $self->_add_joins_with_param('INNER', @_);
}

sub add_left_join {
    my $self = shift;
    $self->_add_joins_with_param('LEFT', @_);
}

1;

__END__
