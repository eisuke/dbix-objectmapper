package Data::ObjectMapper::Session::Query;
use strict;
use warnings;
use Carp::Clan qw(^Data::ObjectMapper::);
use Scalar::Util qw(blessed);
use Log::Any qw($log);
use Data::ObjectMapper::Iterator;

sub new {
    my $class        = shift;
    my $uow          = shift;
    my $mapped_class = shift;
    my $option       = shift;

    my $mapper = $mapped_class->__class_mapper__;
    my $query  = $mapper->table->select;
    return bless {
        mapped_class  => $mapped_class,
        mapper        => $mapper,
        unit_of_work  => $uow,
        query         => $query,
        is_multi      => 0,
        option        => $option,
        alias_table   => +{},
        org_column    => $query->builder->column,
        join_struct   => +{},
    }, $class;
}

sub _query       { $_[0]->{query} }
sub mapper       { $_[0]->{mapper} }
sub unit_of_work { $_[0]->{unit_of_work} }

sub is_multi {
    my $self = shift;
    $self->{is_multi} = shift if @_;
    return $self->{is_multi};
}

sub reset_column {
    my $self = shift;
    $self->_query->column(@{$self->{org_column}});
    return $self->{org_column};
}

{
    no strict 'refs';
    my $pkg = __PACKAGE__;
    for my $meth ( qw( where order_by group_by limit offset
                       add_where add_order_by add_group_by ) ) {
        *{"$pkg\::$meth"} = sub {
            my $self = shift;
            $self->_query->$meth(@_);
            return $self;
        };
    }

    for my $meth ( qw( pager count first ) ) {
        *{"$pkg\::$meth"} = sub {
            my $self          = shift;
            my $uow           = $self->unit_of_work;
            my $mapper        = $self->mapper;
            my $orig_callback = $self->_query->callback;
            local $self->_query->{callback} = sub {
                return $uow->add_storage_object(
                    $mapper->mapping( $orig_callback->(@_), $uow ) );
            };
            $self->_query->$meth(@_);
        };
    }
};

sub _to_alias {
    my $self = shift;
    my @elm = @_;

    for my $i ( 0 .. $#elm ) {
        my $cond = $elm[$i];
        if( ref $cond eq 'ARRAY' ) {
            for my $ci ( 0 .. $#$cond ) {
                if( my $alias = $self->__to_alias($cond->[$ci]) ) {
                    $elm[$i]->[$ci] = $alias;
                }
            }
        }
        else {
            if( my $alias = $self->__to_alias($cond) ) {
                $elm[$i] = $alias;
            }
        }
    }

    return @elm;
}

sub __to_alias {
    my ( $self, $c ) = @_;
    return unless blessed($c) and $c->can('table') and $c->can('as_alias');
    my $alias = $self->{alias_table}{ $c->table } || return;
    if( @$alias > 1 ) {
        $log->warnings(
            '**************************' . $/
          . $c->table . '.' . $c->name . ' has ' . @$alias . ' aliases.'
          . '("' . join('", "', @$alias) . '")' . $/
          . 'converts it into "' . $alias->[0] . '" alias by force.'
          . '**************************'
        );
    }
    return $c->as_alias($alias->[0]);
}

sub join {
    my $self = shift;
    $self->_join( 0, 0, @_ );
    return $self;
}

sub add_join {
    my $self = shift;
    $self->_join( 1, 0, @_ );
    return $self;
}

sub eager_join {
    my $self = shift;
    $self->_join( 0, 1, @_ );
    return $self;
}

sub add_eager_join {
    my $self = shift;
    $self->_join( 1, 1, @_ );
    return $self;
}

sub _join {
    my ( $self, $is_add, $is_eager, @join_conf ) = @_;
    my $join_meth = $is_add ? 'add_join' : 'join';

    my @join;
    my $is_multi = 0;
    for my $conf ( @join_conf ) {
        my ( $join_cond, $join_is_multi ) = $self->_parse_join(
            $conf, $self->mapper, $is_eager ? $self->{join_struct} : +{}
        );
        push @join, @$join_cond;
        $is_multi = 1 if $join_is_multi;
    }

    if( $is_eager ) {
        $self->reset_column unless $is_add;
        $self->_query->add_column( @{$_->[0]->columns} ) for @join;
        $self->is_multi(1) if $is_multi
    }

    return $self->_query->$join_meth(@join);
}

sub _parse_join {
    my ( $self, $join_conf, $class_mapper, $join_struct ) = @_;

    if( ref($join_conf) eq 'HASH' ) {
        my ( $attr, $rel_join ) = %$join_conf;
        my ( $join, $is_multi )
            = $self->_parse_join( $attr, $class_mapper, $join_struct );
        my $rel = $class_mapper->attributes->property($attr);
        my @rel_join
            = ref $rel_join eq 'ARRAY' ? @$rel_join : ($rel_join);
        my $alias = $join->[0][0]->alias_name || $join->[0][0]->table_name;
        my $child_join_struct = $join_struct->{ $alias };
        for my $rj ( @rel_join ) {
            my ( $join_cond, $join_is_multi )
                = $self->_parse_join( $rj, $rel->mapper, $child_join_struct );
            push @$join, @$join_cond;
            $is_multi = 1 if $join_is_multi;
        }
        return $join, $is_multi;
    }
    elsif( ref($join_conf) eq 'ARRAY' ) {
        return [ $join_conf ];
    }
    else {
        my $class_table = $class_mapper->table;
        if( my $class_table_alias
            = $self->{alias_table}->{ $class_table->table_name } ) {
            $class_table = $class_table->clone($class_table_alias->[0]);
        }

        my $rel = $class_mapper->attributes->property($join_conf)
            || confess
            "$join_conf does not exists $self->{mapped_class} attributes.";

        my $alias = $join_conf;
        $alias = $class_table->alias_name . '_' . $alias
            if $class_table->is_clone;
        my $table = $rel->table->clone($alias);

        if( my $org_alias = $self->{alias_table}->{$rel->table->table_name} ) {
            if( my @ex_alias = grep { $_ eq $alias } @$org_alias ) {
                confess "$ex_alias[0] has already been defined.";
            }
            else {
                push @{$self->{alias_table}->{$rel->table->table_name}}, $alias;
            }
        }
        else {
            $self->{alias_table}->{$rel->table->table_name} = [ $alias ];
        }
        my @rel_cond = $rel->relation_condition( $class_table, $table );
        $join_struct->{$alias} = +{};
        return [ [ $table => \@rel_cond ] ], $rel->is_multi;
    }
}

sub execute {
    my $self = shift;

    $self->_query->group_by( @{ $self->mapper->table->columns } )
        unless $self->is_multi;
    my $join = $self->_query->builder->join || [];
    if( @$join ) {
        for my $meth ( qw(where order_by group_by) ) {
            my $orig = $self->_query->builder->$meth;
            next unless $orig and ref $orig eq 'ARRAY';
            $self->_query->$meth($self->_to_alias(@$orig));
        }
    }

    $self->unit_of_work->{query_cnt}++;
    my $uow = $self->unit_of_work;
    my $mapper = $self->mapper;

    if( $self->is_multi ) {
        my $result = [];
        my %settle;
        for my $r ( $self->_query->execute->all ) {
            $self->_join_result_to_object($r);
            my $id = $mapper->primary_cache_key($r);
            if( exists $settle{$id} ) {
                my $i = $settle{$id};
                $self->_merge_result(
                    $result->[$i],
                    $r,
                    $self->{join_struct},
                    $mapper,
                );
            }
            else {
                push @$result, $r;
                $settle{$id} = $#{$result};
            }
        }

        return Data::ObjectMapper::Iterator->new(
            $result,
            $self->_query,
            sub { $uow->add_storage_object( $mapper->mapping(@_) ) }
        );
    }
    else {
        my $orig_callback = $self->_query->callback;
        local $self->_query->{callback} = sub {
            my $result = $orig_callback->(@_);
            $self->_join_result_to_object($result);
            return $uow->add_storage_object(
                $mapper->mapping( $result, $uow )
            );
        };
        return $self->_query->execute;
    }

}

sub _join_result_to_object {
    my ( $self, $r ) = @_;
    my $uow = $self->unit_of_work;
    my $mapper = $self->mapper;

    for my $key ( keys %{$self->{join_struct}} ) {
        if( my $prop = $mapper->attributes->property($key) ) {
            my $obj = $uow->add_storage_object(
                $prop->mapper->mapping($r->{$key})
            );
            if( $prop->is_multi ) {
                $r->{$key} = [ $obj ];
            }
            else {
                $r->{$key} = $obj;
            }
        }
    }
}

sub _merge_result {
    my ( $self, $result, $r, $struct, $mapper ) = @_;

    for my $key ( keys %$struct ) {
        if( my $prop = $mapper->attributes->property($key) ) {
            if ( $prop->is_multi ) {
                push @{ $result->{$key} }, @{$r->{$key}};
            }
            else {
                $result->{$key} = $r->{$key};
            }
        }
    }

}


1;
