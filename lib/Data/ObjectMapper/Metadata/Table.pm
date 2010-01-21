package Data::ObjectMapper::Metadata::Table;
use strict;
use warnings;
use Carp::Clan;
use overload
    '""' => sub {
        my $self = shift;
        my $table_name = $self->table_name;
        $table_name .= ' AS ' . $self->alias_name if $self->is_clone;
        return $table_name;
    },
    fallback => 1
    ;

use Params::Validate qw(:all);
use Scalar::Util;
use List::MoreUtils;
use Clone;

use Data::ObjectMapper::Utils;
use Data::ObjectMapper::Metadata::Table::Column;
use Data::ObjectMapper::Query;

our $DEFAULT_NAMESEP = '.';
my $DEFAULT_COLUMN_METACLASS = 'Data::ObjectMapper::Metadata::Table::Column';
my $DEFAULT_QUERY_CLASS      = 'Data::ObjectMapper::Query';

sub new {
    my $class = shift;

    my ( $table_name, $param ) = validate_pos(
        @_,
        { type => SCALAR|ARRAYREF },
        { type => HASHREF, optional => 1 },
    );

    my @init_attr = (
        +{ table_name        => $table_name },
        +{ engine            => undef },
        +{ primary_key       => +[] },
        +{ unique_key        => +[] },
        +{ foreign_key       => +[] },
        +{ readonly_column   => +[] },
        +{ utf8_column       => +[] },
        +{ column_default    => +{} },
        +{ column_on_update  => +{} },
        +{ column_coerce     => +{} },
        +{ column_validation => +{} },
        +{ autoload_column   => undef },
        +{ column            => +[] },
    );

    my $self = bless +{}, $class;

    $self->{column_metaclass} = $param->{column_metaclass}
        || $DEFAULT_COLUMN_METACLASS;

    confess
        "column_metaclass is not $DEFAULT_COLUMN_METACLASS (or a subclass)"
        unless $self->{column_metaclass}->isa($DEFAULT_COLUMN_METACLASS);

    $self->{query_class} = $param->{query_class} || $DEFAULT_QUERY_CLASS;

    for my $attr ( @init_attr ) {
        my @key = keys %$attr;
        my $meth = $key[0];
        $self->{$meth} = $attr->{$meth};
        $self->${meth}($param->{$meth}) if exists $param->{$meth};
    }

    return $self;
}


=head2 table_name

=cut

sub table_name {
    my $self = shift;

    if( $self->is_clone ) {
        return $self->{table_name}->[0];
    }
    else {
        return $self->{table_name};
    }
}

=head2 alias_name

=cut

sub alias_name {
    my $self = shift;
    return $self->{table_name}->[1] if $self->is_clone;
    return;
}


=head2 engine

=cut

sub engine {
    my $self = shift;

    if( @_ ) {
        my ($engine) = validate_pos(
            @_,
            { type => OBJECT, isa => 'Data::ObjectMapper::Engine' }
        );

        $self->{engine} = $engine;
    }

    return $self->{engine};
}

=head2 primary_key

=cut

sub primary_key {
    my $self = shift;
    $self->__array_accessor('primary_key', @_);
}

sub primary_key_map { $_[0]->{primary_key_map} }

=head2 unique_key

=cut

sub unique_key {
    my $self = shift;

    if( @_ == 2 ) {
        my ( $name, $keys ) = validate_pos(
            @_,
            { TYPE => SCALAR },
            { TYPE => ARRAYREF },
        );

        my $exists = 0;
        for my $uk ( @{$self->{unique_key}} ) {
            $exists++;
            last if $uk->[0] eq $name;
        }

        if( $exists ) {
            return splice(
                @{ $self->{unique_key}},
                ( $exists - 1 ),
                1,
                [ $name, $keys ]
            );
        }
        else {
            push @{$self->{unique_key}}, [ $name, $keys ];
        }

        return [ $name, $keys ];
    }
    elsif( @_ == 1 and !ref($_[0]) ) {
        my $name = shift;
        for my $uk ( @{$self->{unique_key}} ) {
            return $uk->[1] if $uk->[0] eq $name;
        }
    }
    elsif( @_ == 1 and ref($_[0]) eq 'ARRAY' and ref($_[0]->[0]) eq 'ARRAY') {
        return [ map{ $self->unique_key(@$_) } @{$_[0]} ];
    }
    elsif( @_ == 1 && ref($_[0]) eq 'ARRAY' and !ref($_[0]->[0]) ) {
        return $self->unique_key( @{$_[0]} );
    }
    else {
        return $self->{unique_key};
    }
}

=head2 foreign_key

=cut

sub foreign_key {
    my $self = shift;

    if( $_[0] and ref($_[0]) eq 'HASH' ) {
        my @param = %{$_[0]};
        my %foreign_key = validate(
            @param,
            {
                keys  => { type => ARRAYREF },
                table => { type => SCALAR },
                refs  => { type => ARRAYREF},
            }
        );
        push @{$self->{foreign_key}}, \%foreign_key;
    }
    elsif( $_[0] and ref($_[0]) eq 'ARRAY' ) {
        $self->foreign_key($_) for @{$_[0]};
    }

    return $self->{foreign_key};
}

=head2 get_foreign_key_by_col

=cut

sub get_foreign_key_by_col {
    my $self = shift;
    my $col  = shift || return;

    my @foreign_key;
    for my $fk ( @{$self->{foreign_key}} ) {
        if( @{$fk->{keys}} == 1 and !ref($col) ) {
            push( @foreign_key, $fk ) if $fk->{keys}->[0] eq $col;
        }
        elsif( ref($col) eq 'ARRAY' ) {
            my %col_map = map{ $_ => 1 } @$col;
            push( @foreign_key, $fk )
                if List::MoreUtils::all { exists $col_map{$_} }
                @{ $fk->{keys} };
        }
    }

    return \@foreign_key;
}

=head2 get_foreign_key_by_table

=cut

sub get_foreign_key_by_table {
    my $self = shift;
    my $table = shift || return;

    my $table_name = $table->table_name;
    for my $fk ( @{$self->{foreign_key}} ) {
        return $fk if $fk->{table} eq $table_name;
    }
    return;
}

sub __array_accessor {
    my $self = shift;
    my $accessor = shift;

    if( @_ ) {
        my ($array_val) = validate_pos( @_, { type => ARRAYREF } );
        $self->{$accessor} = $array_val;
        my $i = 0;
        $self->{$accessor . '_map'} = +{ map{ $_ => ++$i } @$array_val };
    }

    return $self->{$accessor};
}

sub readonly_column {
    my $self = shift;
    return $self->__array_accessor('readonly_column', @_);
}

sub readonly_column_map { $_[0]->{readonly_column_map} ||= +{} }

sub utf8_column {
    my $self = shift;
    return $self->__array_accessor('utf8_column', @_);
}

sub utf8_column_map { $_[0]->{utf8_column_map} ||= +{} }

sub __hash_accessor {
    my $self = shift;
    my $accessor = shift;

    if( @_ ) {
        my ($hash_val) = validate_pos( @_, { type => HASHREF } );
        my $new_val = Data::ObjectMapper::Utils::merge_hashref(
            $self->{$accessor}, $hash_val,
        );
        $self->{$accessor} = $new_val;
    }
    return $self->{$accessor};
}

sub column_default {
    my $class = shift;
    $class->__hash_accessor('column_default', @_);
}

sub column_on_update {
    my $class = shift;
    $class->__hash_accessor('column_on_update', @_);
}

sub column_coerce {
    my $class = shift;
    $class->__hash_accessor('column_coerce', @_);
}

sub column_validation {
    my $class = shift;
    $class->__hash_accessor('column_validation', @_);
}



=head2 autoload_column

=cut

sub autoload_column {
    my $self = shift;

    confess "autoload_column needs engine."    unless $self->engine;
    confess "autoload_column needs table_name" unless $self->table_name;
    my $engine = $self->engine;
    $self->{column_map} ||= +{};

    my @primary_key = $self->engine->get_primary_key( $self->table_name );
    $self->primary_key(\@primary_key);

    my $uniq_key = $self->engine->get_unique_key( $self->table_name );
    $self->unique_key($uniq_key);

    my $foreign_key = $self->engine->get_foreign_key( $self->table_name );
    $self->foreign_key($foreign_key);

    $self->column( $engine->get_column_info( $self->table_name ) );
}

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
    elsif( @_ == 1 and ref($_[0]) eq 'HASH' ) {
        $self->_set_column($_[0]);
    }
    elsif( @_ == 1 and ref($_[0]) eq 'ARRAY' ) {
        $self->_set_column($_) for @{$_[0]};
    }
    elsif( @_ == 0 ) {
        return @{$self->columns};
    }
    else {
        confess '$obj->column(HashRef|Scalar|Void)';
    }
}

*c = \&column;

sub namesep {
    my $self = shift;
    if( $self->engine ) {
        return $self->engine->namesep;
    }
    else {
        return $DEFAULT_NAMESEP;
    }
}

sub _set_column {
    my $self = shift;

    my $c = shift || return;
    ( ref($c) eq 'HASH' ) || return;

    my $override_column = $self->column_map->{ $c->{name} };
    if ( defined $override_column ) {
        my $org = $self->column( $c->{name} );
        $c = Data::ObjectMapper::Utils::merge_hashref( { %$org }, $c );
    }

    my $name = $c->{name} || confess 'column name not found.';

    my $coarce = $self->column_coerce->{$name} || +{};
    if ( $c->{coerce} ) {
        $coarce
            = Data::ObjectMapper::Utils::merge_hashref( $coarce, $c->{coerce} );
    }

    my $default = $self->column_default->{$name} || do {
        if( $c->{default} ) {
            $self->column_default->{$name} = $c->{default};
        }
        else {
            undef;
        }
    };

    my $on_update = $self->column_on_update->{$name} || do {
        if( $c->{on_update} ) {
            $self->column_on_update->{$name} = $c->{on_update};
        }
        else {
            undef;
        }
    };

    my $is_utf8 = $self->utf8_column_map->{$name} || do {
        if( $c->{utf8} ) {
            push @{$self->utf8_column}, $name;
            $self->utf8_column_map->{$name} = scalar(@{$self->utf8_column});
        }
        else {
            undef;
        }
    };

    my $readonly = $self->readonly_column_map->{$name} || do {
        if ( $c->{readonly} ) {
            push @{ $self->readonly_column }, $name;
            $self->readonly_column_map->{$name}
                = scalar( @{ $self->readonly_column } );
        }
        else {
            undef;
        }
    };

    my $validation = $self->column_validation->{$name} || do {
        if( $c->{validation} ) {
            $self->column_validation->{$name} = $c->{validation};
        }
        else {
            undef;
        }
    };

    my $column_obj = $self->column_metaclass->new(
        name        => $name,
        table       => $self->table_name,
        sep         => $self->namesep,
        type        => $c->{type} || undef,
        size        => $c->{size} || undef,
        is_nullable => $c->{is_nullable} || undef,
        default     => $default,
        on_update   => $on_update,
        utf8        => $is_utf8,
        readonly    => $readonly,
        inflate     => $coarce->{inflate} || undef,
        deflate     => $coarce->{deflate} || undef,
        validation  => $validation,
    );

    if ($override_column) {
        splice( @{ $self->{columns} }, $override_column - 1, 1, $column_obj );
    }
    else {
        push @{ $self->{columns} }, $column_obj;
        $self->column_map->{$name} = scalar( @{ $self->{columns} } );
    }

    return $column_obj;
}

sub columns          { $_[0]->{columns} }
sub column_map       { $_[0]->{column_map} ||= +{} }
sub column_metaclass { $_[0]->{column_metaclass} }

sub query_object {
    my $self = shift;
    return $self->{query_object} ||= $self->{query_class}->new($self->engine);
}

sub select {
    my $self = shift;
    return $self->query_object->select( $self->_select_query_callback )
        ->column(@{$self->columns})->from( $self );
}

sub _select_query_callback {
    my $self = shift;
    return sub {
        my ( $result, $query ) = @_;

        my $column = @{$query->column} > 0 ? $query->column : $self->columns;
        my %result;

        for my $i ( 0 .. $#{$column} ) {
            next unless defined $result->[$i];
            my $col_obj = $self->_get_column_object_from_query( $column->[$i] );
            if( ref $column->[$i] eq 'ARRAY' ) { # AS(alias)
                if( $col_obj ) {
                    if ( $col_obj->table eq $self->table_name ) {
                        $result{ $column->[$i][1] }
                            = $col_obj->from_storage( $result->[$i] );
                    }
                    else {
                        $result{ $col_obj->table }->{ $column->[$i][1] }
                            = $col_obj->from_storage($result->[$i]);
                    }
                }
                else {
                    $result{$column->[$i][1]} = $result->[$i];
                }
            }
            elsif( ref $column->[$i] eq 'HASH' ) { # Function
                $result{( keys %{ $column->[$i] } )[0]} = $result->[$i];
            }
            else {
                if ( $col_obj->table eq $self->table_name ) {
                    $result{ $col_obj->name }
                        = $col_obj->from_storage( $result->[$i] );
                }
                else {
                    $result{$col_obj->table}->{$col_obj->name}
                        = $col_obj->from_storage( $result->[$i] );
                }
            }
        }

        return \%result;
    };
}

sub _get_column_object_from_query {
    my ( $self, $c ) = @_;

    if( ref($c) eq $self->column_metaclass ) {
        return $c;
    }
    elsif ( ref($c) eq 'ARRAY' ) { # alias
        return $self->_get_column_object_from_query( $c->[0] );
    }
    elsif( ref($c) eq 'HASH' ) { # function
        my $val = ( values %$c )[0];
        if( ref $val eq 'ARRAY' ) {
            for my $v ( @$val ) {
                if( my $r = $self->_get_column_object_from_query($v) ) {
                    return $r;
                }
            }
        }
        else {
            return $self->_get_column_object_from_query($val);
        }
    }
    elsif( !ref($c) && $self->c($c) ) {
        return $self->c($c)
    }
    else {
        return;
    }
}

sub count {
    my $self = shift;
    return $self->query_object->count->from( $self );
}

sub find {
    my $self = shift;
    my $cond = shift;
    my ( $type, @cond ) = $self->get_unique_condition($cond);
    confess "condition is not unique." unless @cond;
    $self->_find(@cond);
}

sub _find {
    my $self = shift;
    return $self->select->where(@_)->execute->first;
}

sub get_unique_condition {
    my ( $self, $cond ) = @_;

    if ( ref $cond eq 'HASH' ) {
        my $ok = 0;
        if( List::MoreUtils::all { $cond->{$_} } @{ $self->primary_key } ) {
            return (
                undef,
                map { $self->c($_) == $cond->{$_} } @{ $self->primary_key }
            );
        }
        else {
            for my $uinfo ( @{ $self->unique_key } ) {
                if( List::MoreUtils::all { $cond->{$_} } @{$uinfo->[1]} ) {
                    return (
                        $uinfo->[0],
                        map { $self->c($_) == $cond->{$_} } @{ $uinfo->[1] }
                    );
                }
            }
        }
    }
    elsif ( ref $cond eq 'ARRAY'
        and !ref $cond->[0]
        and @$cond == @{ $self->primary_key } )
    {
        return (
            undef,
            map { $self->c($_) == shift(@$cond) } @{ $self->primary_key }
        );
    }
    elsif ( ref $cond eq 'ARRAY'
        and ref $cond->[0] eq 'ARRAY'
        and ref $cond->[0][0] eq $self->column_metaclass )
    {
        my %col;
        for my $c (@$cond) {
            return unless $c->[1] eq '=';
            $col{ $c->[0]->name } = $c->[2];
        }
        return $self->get_unique_condition( \%col );
    }
    elsif ( !ref $cond and defined $cond ) {
        if( @{ $self->primary_key } == 1 ) {
            return (
                undef,
                map { $self->c($_) == $cond } @{ $self->primary_key }
            );
        }
    }

    return;
}

sub insert {
    my $self = shift;
    return $self->query_object->insert(
        $self->_insert_query_callback,
        $self->primary_key
    )->into( $self->table_name );
}

sub _insert_query_callback {
    my $self = shift;

    return sub {
        my $query = shift;
        my $input_val = $query->values;
        return unless ref($input_val) eq 'HASH'; # XXXXX

        for my $c ( @{ $self->columns } ) {
            if ( my $val = $c->to_storage( $input_val->{ $c->name } ) ) {
                $query->values->{ $c->name } = $val;
            }
        }
    };
}

sub delete {
    my $self = shift;
    return $self->query_object->delete( $self->_delete_query_callback )
        ->table( $self->table_name );
}

sub _delete_query_callback { undef } # TODO cascade delete

sub update {
    my $self = shift;
    return $self->query_object->update( $self->_update_query_callback )
        ->table( $self->table_name );
}

sub _update_query_callback {
    my $self = shift;

    return sub {
        my $query = shift;
        for my $c ( @{ $self->columns } ) {
            if ( my $val
                = $c->to_storage_on_update( $query->set->{ $c->name } ) )
            {
                $query->set->{ $c->name } = $val;
            }
        }
    };
}

=head2 clone

=cut

sub clone {
    my $self = shift;
    my $alias = shift;

    my $clone = Clone::clone($self);
    $clone->{table_name} = [ $clone->table_name, $alias ];
    for my $c ( @{$clone->columns} ) {
        $c->{table} = $alias;
    }

    return $clone;
}

=head2 is_clone

=cut

sub is_clone { ref($_[0]->{table_name}) eq 'ARRAY' }

1;

__END__
