package Data::ObjectMapper::Session::Query;
use strict;
use warnings;
use Carp::Clan;
use Data::ObjectMapper::Iterator;

sub new {
    my $class        = shift;
    my $uow          = shift;
    my $mapped_class = shift;
    my $option       = shift;

    my $mapper = $mapped_class->__class_mapper__;
    my $query  = $mapper->table->select;
    return bless {
        mapper        => $mapper,
        unit_of_work  => $uow,
        query         => $query,
        is_multi      => 0,
        option        => $option,
        alias_table   => +{},
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
            my $self = shift;
            $self->_query->$meth(@_);
        };
    }
};

sub _to_alias {
    my $self = shift;

    for my $i ( 0 .. $#_ ) {
        my $cond = $_[$i];
        if( ref $cond eq 'ARRAY' ) {
            for my $ci ( 0 .. $#$cond ) {
                my $c = $cond->[$ci];
                if ( ref($c) eq 'Data::ObjectMapper::Metadata::Table::Column'
                    and my $alias = $self->{alias_table}{ $c->table } )
                {
                    my $clone = $c->clone;
                    $clone->{table} = $alias;
                    $_[$i]->[$ci] = $clone;
                }
            }
        }
        else {
            if ( ref($cond) eq 'Data::ObjectMapper::Metadata::Table::Column'
                and my $alias = $self->{alias_table}{ $cond->table } )
            {
                my $clone = $cond->clone;
                $clone->{table} = $alias;
                $_[$i] = $clone;
            }
        }
    }

    return @_;
}

sub join {
    my $self = shift;
    my $join_attr = shift;
    $join_attr = [ $join_attr ] unless ref $join_attr eq 'ARRAY';
    my $class_mapper = $self->mapper;

    my @join;
    for my $attr ( @$join_attr ) {
        my $rel = $class_mapper->attributes->property($attr)->{isa};
        $self->{alias_table}->{$rel->table->table_name} = $attr;
        my $table = $rel->table->clone($attr);
        my @rel_cond = $rel->relation_condition($class_mapper, $table);
        push @join, [ $table => [ @rel_cond ] ];

        if( $self->{option}{eagerload} ) {
            $self->_query->add_column( @{$table->columns} );
            $self->is_multi(1) if $rel->is_multi
        }
    }

    $self->_query->join(@join);
    $self->_query->group_by( @{ $class_mapper->table->columns } )
        unless $self->{option}{eagerload};
    return $self;
}

sub add_join {

}

sub execute {
    my $self = shift;

    my $join = $self->_query->builder->join || [];
    if( @$join ) {
        for my $meth ( qw(where column order_by group_by) ) {
            my $orig = $self->_query->builder->$meth;
            next unless $orig and ref $orig eq 'ARRAY';
            $self->_query->$meth($self->_to_alias(@$orig));
        }
    }

    $self->unit_of_work->{query_cnt}++;
    my $uow = $self->unit_of_work;
    my $mapper = $self->mapper;

    if( $self->is_multi ) {
        my @result;
        my %settle;
        for my $r ( $self->_query->execute->all ) {
            my $id = $mapper->primary_cache_key($r);
            my @rels;
            for my $key ( keys %$r ) {
                next if $mapper->table->c($key);
                my $rel = $mapper->attributes->property($key)->{isa};
                my $obj = $rel->mapper->mapping($r->{$key});
                $self->unit_of_work->add_storage_object($obj);
                push @rels, $key;
                $r->{$key} = $obj;
            }

            if( my $i = $settle{$id} ) {
                $i -= 1;
                for my $key ( @rels ) {
                    if( $result[$i]->{$key} ) {
                        if( ref $result[$i]->{$key} eq 'ARRAY') {
                            push @{$result[$i]->{$key}}, $r->{$key};
                        }
                        else {
                            $result[$i]->{$key} = [ $result[$i]->{$key}, $r->{$key} ];
                        }
                    }
                    else {
                        $result[$i]->{$key} = $r->{$key};
                    }
                }
            }
            else {
                push @result, $r;
                $settle{$id} = scalar(@result);
            }
        }

        return Data::ObjectMapper::Iterator->new(
            \@result,
            $self->_query,
            sub { $uow->add_storage_object( $mapper->mapping(@_) ) }
        );
    }
    else {
        my $orig_callback = $self->_query->callback;
        local $self->_query->{callback} = sub {
            return $uow->add_storage_object(
                $mapper->mapping( $orig_callback->(@_) )
            );
        };
        return $self->_query->execute;
    }

}

1;
