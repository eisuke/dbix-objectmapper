package Data::ObjectMapper::SQL::Base;
use strict;
use warnings;
use Carp qw(croak);

use Clone;
use base qw(Class::Data::Inheritable);

__PACKAGE__->mk_classdata( initdata => {} );
__PACKAGE__->mk_classdata( accessors => {} );
__PACKAGE__->mk_classdata(
    limit_syntax => {
        default  => 'limit_xy',
        pg       => 'limit_offset',
        pgpp     => 'limit_offset',
        sqlite   => 'limit_offset',
        sqlite2  => 'limit_offset',
    }
);

sub import {
    my $class = shift;

    no strict 'refs';
    my %accessors = %{ $class->accessors };
    for my $func ( keys %accessors ) {
        for my $accessor ( @{$accessors{$func}} ) {
            *{"$class\::$accessor"} = sub {
                use strict 'refs';
                my $self = shift;
                return $self->_accessor($accessor, @_);
            } unless $class->can($accessor);

            *{"$class\::add_$accessor"} = sub {
                use strict 'refs';
                my $self = shift;
                return $self->_add_accessor($accessor, @_);
            } unless $class->can('add_' . $accessor);

            *{"$class\::${accessor}_as_sql"} = sub {
                use strict 'refs';
                my $self = shift;
                return $self->_as_sql_accessor($accessor, $func, @_);
            } unless $class->can( $accessor . '_as_sql' );
        }
    }
}

sub _accessor {
    my $self = shift;
    my $field = shift;

    if( @_ == 1 and !defined $_[0] ) {
        $self->{$field} = [];
    }
    elsif( @_ ) {
        $self->{$field} = \@_;
        return $self;
    }
    else {
        return $self->{$field};
    }
}

sub _add_accessor {
    my $self = shift;
    my $field = shift;
    if( @_ ) {
        push @{$self->{$field}}, @_;
    }
    return $self;
}

sub _as_sql_accessor {
    my ( $self, $field, $func ) = @_;
    my @param
        = ref $self->{$field} eq 'ARRAY'
        ? @{ $self->{$field} }
        : ( $self->{$field} );

    return $self->$func(@param);
}

sub new {
    my $class = shift;
    my $self = bless {
        %{$class->initdata},
    }, $class;

    $self->_init(@_) if @_;
    return $self;
}

sub _init {
    my ( $self, %opt ) = @_;

    for my $opt_key ( keys %{ $self->initdata } ) {
        if( exists $opt{$opt_key} ) {
            my $value;
            if( ref $self->initdata->{$opt_key} eq 'ARRAY' ) {
                $value = $self->cast_arrayref($opt{$opt_key});
            }
            else {
                $value = $opt{$opt_key};
            }
            $self->{$opt_key} = $value;
        }
    }

    return $self;
}

sub as_sql { die 'Abstract Method' }

sub cast_arrayref {
    my $class = shift;
    my $value = shift || return;
    return ref $value eq 'ARRAY' ? $value : [$value];
}

sub convert_columns_to_sql {
    my $class = shift;
    return unless @_;

    return join ', ', map {
        $class->convert_column_alias_to_sql(
            $class->convert_func_to_sql($_) );
    } grep { defined $_ } @_;
}

sub convert_func_to_sql {
    my ($class, $func) = @_;
    return unless $func;
    return $func unless $func and ref $func eq 'HASH';

    my $key   = ( keys %$func )[0];
    my $value = $func->{$key};
    my @param = ref $value eq 'ARRAY' ? @$value : $value;
    return
      uc($key)
      . '('
      . join( ',', map { $class->convert_func_to_sql($_) } @param )
      . ')';
}

sub convert_column_alias_to_sql {
    my ($class, $param) = @_;
    return $param unless $param and ref $param eq 'ARRAY';
    my $col = $class->convert_func_to_sql( $param->[0] );
    my $alias = $param->[1];
    if( $col and $alias ) {
        return $col . ' AS ' . $alias;
    }
    else {
        return $col;
    }
}

sub convert_tables_to_sql {
    my $class = shift;
    my @stm;
    my @bind;

    for my $t ( @_ ) {
        my ($table_stm, @table_bind) = $class->convert_table_to_sql(@_);
        push @stm, $table_stm;
        push @bind, @table_bind if @table_bind;
    }

    return join( ',', @stm ), @bind;
}

sub convert_table_to_sql {
    my ( $class, $table ) = @_;

    my ($stm, @bind);
    if( ref $table eq 'ARRAY' ) {
        my ($t_stm, @t_bind) = $class->convert_table_to_sql( $table->[0] );
        $stm = $t_stm . ' AS ' . $table->[1];

        push @bind, @t_bind if @t_bind;
    }
    elsif( ref $table eq 'Data::ObjectMapper::SQL::Select' ) {
        my ( $sub_stm, @sub_bind ) = $table->as_sql;
        $stm = '( ' . $sub_stm . ' )';
        @bind = @sub_bind;
    }
    else {
        $stm = $table . q{};
    }

    return $stm, @bind;
}

sub convert_joins_to_sql {
    my ($class, @joins) = @_;

    my @join_stm;
    my @join_bind;
    for my $j ( @joins ) {
        my ( $stm, @bind ) = $class->convert_join_to_sql(@$j);
        push @join_stm, $stm;
        push @join_bind, @bind;
    }

    return  join(' ', @join_stm), @join_bind;
}

sub convert_join_to_sql {
    my ($class, $table, $cond, $type ) = @_;

    my @bind;
    my $stm = uc($type) || 'LEFT OUTER';
    my ( $table_stm, @table_bind ) = $class->convert_table_to_sql($table);
    $stm .= ' JOIN ' . $table_stm;
    push @bind, @table_bind if @table_bind;

    if( ref $cond eq 'ARRAY' ) {
        my ( $stm_cond, @bind_cond ) = $class->build_where(@$cond);
        $stm .= ' ON ' . $stm_cond;
        push @bind, @bind_cond;
    }
    elsif( not ref $cond ) {
        $stm .= ' USING(' . $cond . ')';
    }

    return ( $stm, @bind );
}

sub build_where {
    my ( $class, @where ) = @_;
    return $class->convert_conditions_to_sql('and', @where);
}

sub convert_conditions_to_sql {
    my ($class, $logic_op, @where) = @_;
    return unless $logic_op and @where;

    my ($stm, @bind);
    for my $w (@where) {
        $stm .= ' ' . uc($logic_op) . ' ' if $stm;

        if( ref $w eq 'ARRAY' ) {
            my ( $stm_where, @bind_where ) =
              $class->convert_condition_to_sql($w);
            $stm .= $stm_where;
            push @bind, @bind_where;
        }
        elsif( ref $w eq 'HASH' ) {
            my $op   = ( keys %$w )[0];
            my $cond = $w->{$op};
            if ( my ( $stm_op, @bind_op ) =
                $class->convert_conditions_to_sql( $op, @{$cond} ) )
            {
                $stm .= $stm_op;
                push @bind, @bind_op;
            }
        }
        else {
            $stm .= $w;
        }
    }

    return ( '( ' . $stm . ' )', @bind );
}

sub convert_condition_to_sql {
    my ($class, $w ) = @_;
    return unless @$w;

    my @bind;
    my $stm = $class->convert_func_to_sql($w->[0]);
    splice @$w, 1, 0, '=' if @$w == 2;

    if( @$w == 3 ) {
        splice @$w, 1, 1, '!=' if $w->[1] eq '<>';

        if ( ref $w->[2] eq 'ARRAY' ) {
            if (   $w->[1] eq '='
                or $w->[1] eq '!='
                or lc( $w->[1] ) =~ /^\s*(?:not\s*)*in\s*$/ )
            {
                $stm .= ' NOT' if $w->[1] eq '!=' or $w->[1] =~ /not/;
                $stm .= ' IN (' . join(',', ('?') x @{$w->[2]} ) . ')';
                push @bind,
                  map { $class->convert_val_to_sql_format($_) } @{ $w->[2] };
            }
            elsif( uc($w->[1]) eq 'BETWEEN' and @{$w->[2]} == 2 ) {
                $stm .= ' BETWEEN ? AND ?';
                push @bind,
                  map { $class->convert_val_to_sql_format($_) } @{ $w->[2] };
            }
            else {
                croak 'Invalid Parameters in WHERE clause.('.join(',',@$w).')';
            }
        }
        elsif( not defined $w->[2] ) {
            if( $w->[1] eq '!=' ) {
                $stm .= ' IS NOT NULL';
            }
            elsif( $w->[1] eq '=' ) {
                $stm .= ' IS NULL';
            }
        }
        elsif( ref $w->[2] eq 'SCALAR' ) {
            $stm .= ' '
              . uc( $w->[1] ) . ' '
              . ${ $w->[2] };
        }
        # for array column for pg
        elsif( ref $w->[2] eq 'REF' ) {
            $stm .= ' ' . uc($w->[1]) . ' ?';
            push @bind, $class->convert_val_to_sql_format($w->[2]);
        }
        else {
            $stm .= ' ' . uc($w->[1]) . ' ?';
            push @bind, $w->[2];
        }
    }
    else {
        croak 'Short of parameters in WHERE clause';
    }

    return ( $stm, @bind );
}

sub convert_val_to_sql_format {
    my ( $class, $val ) = @_;

    if( ref $val eq 'REF' and ref $$val eq 'ARRAY' ) {
        return '{' . join(',', @$$val ) . '}';
    }
    elsif( ref $val eq 'ARRAY' ) {
        return '{' . join(',', @$val ) . '}';
    }
    else {
        return $val;
    }
}

sub num_check {
    my ($self, $num) = @_;
    croak "Non-numerics in limit/offset clause ($num)" if $num =~ /\D/;
    return $num;
}

sub limit_offset {
    my $self = shift;

    my $stm;
    if( my $limit = $self->limit_as_sql ) {
        $stm .= ' LIMIT ' . $limit;
    }

    if( my $offset = $self->offset_as_sql ) {
        $stm .= ' OFFSET ' . $offset;
    }

    return $stm;
}

sub limit_xy {
    my $self = shift;

    my $stm = ' LIMIT ';
    if( my $offset = $self->offset_as_sql ) {
        $stm .= $offset . ', ';
    }

    if( my $limit = $self->limit_as_sql ) {
        $stm .= $limit;
    }

    return $stm;
}

sub clone {
    my $self = shift;
    my $clone_data = Clone::clone($self);
    return bless $clone_data, ref($self);
}

1;

__END__
