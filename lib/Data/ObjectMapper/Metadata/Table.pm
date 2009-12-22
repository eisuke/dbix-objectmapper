package Data::ObjectMapper::Metadata::Table;
use strict;
use warnings;
use Carp::Clan;
use overload
    '""' => sub { $_[0]->table_name },
    fallback => 1
    ;

use Params::Validate qw(:all);
use Scalar::Util;
use List::MoreUtils;

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
        { type => SCALAR },
        { type => HASHREF, optional => 1 },
    );

    my @init_attr = (
        +{ table_name        => $table_name },
        +{ engine            => undef },
        +{ schema_name       => undef },
        +{ primary_key       => +[] },
        +{ unique_key        => +[] },
        +{ temp_column       => +[] },
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

sub table_name { $_[0]->{table_name} }

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

=head2 schema_name

=cut

sub schema_name {
    my $self = shift;
    $self->{schema_name} = shift if @_;
    return $self->{schema_name};
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

sub temp_column {
    my $self = shift;
    return $self->__array_accessor('temp_column', @_);
}

sub temp_column_map { $_[0]->{temp_column_map} ||= +{} }

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
        ->column(@{$self->columns})->from( $self->table_name );
}

sub _select_query_callback {
    my $self = shift;
    return sub {
        my ( $result, $query ) = @_;

        my $column = @{$query->column} > 0 ? $query->column : $self->columns;
        my %result;

        for my $i ( 0 .. $#{$column} ) {
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
        return undef;
    }
}

sub count {
    my $self = shift;
    return $self->query_object->count->from( $self->table_name );
}

sub find {
    my $self = shift;
    my $cond = shift;
    my @cond = $self->get_unique_condition($cond);
    confess "condition is not unique." unless @cond;
    return $self->select->where(@cond)->execute->first;
}

sub get_unique_condition {
    my ( $self, $cond ) = @_;

    if ( ref $cond eq 'HASH' ) {
        my $ok = 0;
        if( List::MoreUtils::all { $cond->{$_} } @{ $self->primary_key } ) {
            return map { $self->c($_) == $cond->{$_} } @{ $self->primary_key };
        }
        else {
            for my $uinfo ( @{ $self->unique_key } ) {
                if( List::MoreUtils::all { $cond->{$_} } @{$uinfo->[1]} ) {
                    return map { $self->c($_) == $cond->{$_} } @{$uinfo->[1]};
                }
            }
        }
    }
    elsif ( ref $cond eq 'ARRAY' and !ref $cond->[0] ) {
        return map { $self->c($_) == shift(@$cond) } @{ $self->primary_key }
            if @$cond == @{ $self->primary_key };
    }
    elsif ( ref $cond eq 'ARRAY'
        and ref $cond->[0] eq 'ARRAY'
        and ref $cond->[0][0] eq $self->column_metaclass )
    {
        my %col;
        for my $c (@$cond) {
            return unless $c->[1] eq '=';
            $col{ $c->[0]->name } = 1;
        }
        return $self->get_unique_condition( \%col );
    }
    elsif ( !ref $cond and defined $cond ) {
        if( @{ $self->primary_key } == 1 ) {
            return map { $self->c($_) == $cond } @{ $self->primary_key };
        }
    }

    return;
}


sub insert {
    my $self = shift;
    return $self->query_object->insert(
        $self->_insert_query_callback,
        $self->primary_key
    )->table( $self->table_name );
}

sub _insert_query_callback {
    my $self = shift;

    return sub {
        my $query = shift;
        for my $c ( @{ $self->columns } ) {
            if ( my $val = $c->to_storage( $query->values->{ $c->name } ) ) {
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

=pod

check...

    my @primary_key
        = map { $column_name_to_alias{$_} } @{ $class->provided_primary_key };

    my @unique_key;
    for my $uk ( @{$class->provided_unique_key} ) {
        my @u_keys;
        for my $i ( 0 .. $#{$uk->[1]} ) {
            push(
                @u_keys,
                $column_name_to_alias{$uk->[1][$i]} || $uk->[1][$i]
            );
        }
        push @unique_key, [ $uk->[0], \@u_keys ];
    }
    $class->unique_key( \@unique_key );

    return @columns;


=cut

=head2 relationship

 relationship => {
       has_many => {
            cds => { class_name => 'My::Cds' },
       },

       has_one => {
            desc => 'My::Description',
       },
 };

=cut

1;

__END__


sub relationship {
    my $self = shift;

    if( @_ == 1 and !ref($_[0]) ) {
        my $rel_name = shift || return;
        $self->{relationship}{$rel_name};
    }
    elsif( @_ == 1 and ref($_[0]) eq 'HASH' ) {
        my $relation_struct = shift;
        for my $type ( keys %$relation_struct ) {
            $self->set_relationship( $type, $_, $relation_struct->{$_} )
                for keys %{ $relation_struct->{$type} };
        }
    }

    else {
        $self->{relationship};
    }
}

my @rel_types = (
    'belongs_to', 'might_belongs_to', 'has_many', 'has_one',
    'might_have', 'many_to_many',
);

sub enable_relation_type {
    my $rel = shift;
    return grep { $rel eq $_ } @rel_types;
}

sub set_relationship {
    my $self = shift;

    my ( $type, $rel_name, $option ) = validate_pos(
        @_,
        {   type      => SCALAR,
            callbacks => { enable_type => \&enable_relation_type }
        },
        { type => SCALAR },
        { type => HASHREF | SCALAR, },
    );

    my $method = '_resolve_relationship_' . $type;
    $self->$method(@_);
}

sub _resolve_relationship_belongs_to {
    my ( $self, $col_name, $option, $is_might_belongs_to ) = @_;

    my $type = $is_might_belongs_to ? 'might_belongs_to' : 'belongs_to';

    my $column = $self->column($col_name)
      || $self->exception("column $col_name not found.");

    $option = { class_name => $option } if $option and !ref $option;
    my $klass = $option->{class_name};

    my $rel_cond;
    my $inflate_col;
    if ( exists $option->{conditions} and ref $option->{conditions} ) {
        $rel_cond = $klass->resolve_condition( $option->{conditions} );

        for my $rc ( @$rel_cond ) {
            for my $col ( @$rc ) {
                if( $self->is_col_object($col) ) {
                    $inflate_col = $col;
                    last;
                }
            }
        }
    }
    elsif ( ref $option eq 'HASH' and exists $option->{foreign_key} ) {
        $inflate_col = $klass->column($option->{foreign_key});
        $rel_cond = [ [ $column, $inflate_col ] ];
    }
    else {
        my ( $pkey, $too_many_pkey ) = @{ $klass->primary_key };

        $self->exception("belongs_to needs a primary key. ${klass} has none.")
          unless defined $pkey;

        $self->exception('belongs_to can only for a single primary key')
          if defined $too_many_pkey;

        $inflate_col = $klass->column($pkey);
        $rel_cond = [ [ $column, $inflate_col ] ];
    }

    unless( $klass->is_uniq_condition($rel_cond) ) {
        $self->exception(
            "Can't get unique condition of belongs_to relation : " . $col_name
        );
    }

    my $col = $column->alias || $column->name;
    $column->set_inflate(
        sub{
            my $val = shift;
            my $self = shift;

            return unless defined $val;

            unless( exists $self->rel_value->{$col} ) {
                if( ref $val eq 'HASH' ) {
                    $self->rel_value->{$col} = $klass->_load_or_new($val);
                }
            }

            return $self->_get_rel_value($col);
        }
    );

    my $key_name = $inflate_col->alias || $inflate_col->name;
    $column->set_deflate(
        sub {
            my $obj = shift;
            if( ref($obj) eq $klass->_repository ){
                return $obj->$key_name;
            }
            elsif( ref($obj) eq 'HASH' ) {
                my $factory = $klass->new($obj)->save; # Hmm...
                return $factory->$key_name;
            }
            else {
                exception("Can't deflate belongs_to object.");
            }
        }
    );

    $option->{join_type} ||= 'inner';
    $option->{cond} = $rel_cond;
    $option->{type} = 'belongs_to';
    $option->{cascade_delete} ||= 0;
    $option->{cascade_copy}   ||= 0;
    $option->{cascade_update} ||= 0;
    $self->_relationship->{$self->schema_name}{$col_name} = $option;
}

sub _resolve_relationship_might_belongs_to {
    my ( $class, $name ) = @_;
    $class->provided_relationship->{might_belongs_to}{$name}{join_type} = 'left';
    $class->__belongs_to( $name, 1 );
}

sub _resolve_relationship_has_many {
    my ( $class, $name ) = @_;

    my $option = delete $class->_relationship->{$class}{has_many}{$name};

    if ( $class->repository_class->can($name) ) {
        $class->exception(
            "$name is already reserved. Please set another name." );
    }

    my @guess;
    if( exists $option->{class_name} ) {
        push @guess, $option->{class_name};
    }
    else {
        push @guess, $name, $class->plural_to_singular_func->($name);
    }

    my $klass;
    for my $klass_name ( @guess ) {
        $klass = $class->schema->get( $klass_name ) unless $klass;
    }

    $class->exception("$class : Relation Class $name not found.")
      unless $klass;
    $option->{class_name} = $klass;

    my $rel_cond =
      $class->_get_relationship_condition( $klass, $option, 'has_many' );

    $class->_repository->metaclass->add_method(
        $name => sub {
            my $self = shift;
            return $self->_get_rel_value($name, @_);
        }
    );

    $class->_factory->metaclass->add_method(
        $name => sub {
            my ( $self, $val ) = @_;

            if ( $val ) {
                $self->_set_rel_value( $name, $val );
            }

            my $rel = $self->{rel_value}{$name} || return;
            return wantarray() ? $rel->all : $rel;
        }
    );

    $option->{cond} = $rel_cond;
    $option->{join_type}      ||= 'left';
    $option->{cascade_delete} ||= 0;
    $option->{cascade_copy}   ||= 0;
    $option->{cascade_update} ||= 0;
    $option->{type} = 'has_many';

    $class->_relationship->{$class->schema_name}{$name} = $option;
}

sub _resolve_relationship_has_one {
    my ( $class, $name, $is_might_have ) = @_;

    my $type = $is_might_have ? 'might_have' : 'has_one';
    my $option = delete $class->_relationship->{$class}{$type}{$name};
    if ( $class->repository_class->can($name) ) {
        $class->exception(
            "$name is already reserved. Please set another name." );
    }

    my $klass_name = $option->{class_name} || $name;
    my $klass = $class->schema->get($klass_name)
      || $class->exception("class $klass_name not found.");
    $option->{class_name} = $klass;

    my $rel_cond =
      $class->_get_relationship_condition( $klass, $option, 'has_one' );

    $class->_repository->metaclass->add_method(
        $name => sub {
            my $self = shift;
            $self->_get_rel_value( $name );
        }
    );

    $class->_factory->metaclass->add_method(
        $name => sub {
            my ( $self, $val ) = @_;

            if ( $val ) {
                $self->_set_rel_value( $name, $val );
            }

            return $self->{rel_value}{$name};
        }
    );

    $option->{cond} = $rel_cond;
    $option->{join_type}      ||= 'inner';
    $option->{cascade_delete} ||= 0;
    $option->{cascade_copy}   ||= 0;
    $option->{cascade_update} ||= 0;
    $option->{type} = $type;

    $class->_relationship->{$class->schema_name}{$name} = $option;
}

sub _resolve_relationship_might_have {
    my ( $class, $name ) = @_;
    my $option = $class->_relationship->{$class}{might_have}{$name};
    $option->{join_type} ||= 'left';
    $class->__has_one( $name, 1 );
}

sub _resolve_relationship_many_to_many {
    my ( $class, $name ) = @_;

    my $option = delete $class->_relationship->{$class}{many_to_many}{$name};

    if (   $class->repository_class->can($name)
        || $class->repository_class->can( 'add_' . $name )
        || $class->repository_class->can( 'remove_' . $name ) )
    {
        $class->exception(
            "$name is already reserved. Please set another name.");
    }

    my ( $method, $key, $rel_class );
    if ( $method = $option->{inter_rel} ) {
        my $inter_info = $class->relationship( $option->{inter_rel} )
          || $class->exception(
            "$class needs in relation to " . $option->{inter_rel} );
        $key = $option->{inter_rel_key} || $name;

        my $inter_rel = $inter_info->{class_name}->relationship($key)
          || $class->exception(
            $inter_info->{class_name} . " needs in relation to " . $key );

        $class->exception( $inter_rel->{class_name}
              . "'s relation type is "
              . $inter_rel->{type}
              . ". it needs belongs_to." )
          unless $inter_rel->{type} eq 'belongs_to';

        $rel_class = $inter_info->{class_name};
    }
    else {
        $rel_class =
             $class->schema->get( $option->{inter_class} )
          || $class->schema->get( $class->schema_name . '_' . $name )
          || $class->schema->get( $name . '_' . $class->schema_name );

        $class->exception( "relationship class not found." ) unless $rel_class;

        $option->{inter_rel} = $rel_class;
        $key = $option->{inter_rel_key} || $name;
        $option->{inter_rel_key} = $key;
        $method = $rel_class->schema_name;

        my $inter_rel = $rel_class->relationship($key)
          || $class->exception( $rel_class . " needs in relation to " . $key );

        $class->exception( $inter_rel->{class_name}
              . "'s relation type is "
              . $inter_rel->{type}
              . ". it needs belongs_to." )
          unless $inter_rel->{type} eq 'belongs_to';

        my $rel = $class->relationship($method) || do {
            my %add_cond;
            if ( exists $option->{inter_rel_options} ) {
                %add_cond = %{ $option->{inter_rel_options} };
            }

            $class->_relationship->{$class}{has_many}{$method} = {
                class_name => $method,
                %add_cond,
            };
            $class->__has_many($method);
        };
    }

    $class->_repository->metaclass->add_method(
        $name => sub {
            my $self = shift;

            unless( $self->anon_value->{$name} ) {
                my @rel_rs = $self->$method(@_);
                my @foreign_rel = map { $_->$key } @rel_rs;

                $self->anon_value->{$name} = Data::ObjectMapper::Iterator->new(
                    $rel_class->relationship($key => 'class_name'),
                    \@foreign_rel
                );
            }

            my $it = $self->anon_value->{$name};
            return wantarray ? @$it : $it;
        },
    );

    $class->_repository->metaclass->add_method(
        'add_' . $name => sub {
            my $self = shift;
            my $many_class = $rel_class->relationship( $key => 'class_name' );

            my $obj;
            if( ref($_[0]) eq $many_class->_factory ) {
                $obj = $_[0]->save;
            }
            elsif( ref($_[0]) eq $many_class->_repository ) {
                $obj = $_[0];
            }
            elsif( ref($_[0]) eq 'HASH' ) {
                $obj = $many_class->create($_[0]);
            }
            elsif( @_ ) {
                $obj = $many_class->create({@_});
            }
            else {
                return;
            }

            my $rel_cond = $rel_class->relationship( $key => 'cond' );

            my %create_data;
            for my $rc ( @$rel_cond ) {
                my $accessor = $rc->[0]->alias || $rc->[0]->name;
                my $f_name   = $rc->[1]->alias || $rc->[1]->name;
                $create_data{$accessor} = $obj->$f_name;
            }

            my $self_cond = $self->meta->relationship( $method => 'cond' );
            for my $rc ( @$self_cond ) {
                my $accessor = $rc->[0]->alias || $rc->[0]->name;
                my $f_name   = $rc->[1]->alias || $rc->[1]->name;
                $create_data{$f_name} = $self->$accessor;
            }

            $rel_class->create(\%create_data);
            delete $self->rel_value->{$method};
            delete $self->anon_value->{$name};

            return $obj;
        }
    );

    $class->_repository->metaclass->add_method(
        'remove_' . $name => sub {
            my $self = shift;
            my $many_class = $rel_class->relationship( $key => 'class_name' );

            my $obj;
            if( ref($_[0]) eq $many_class->_repository ) {
                $obj = $_[0];
            }
            elsif( $_[0] ) {
                $obj = $many_class->find($_[0]);
            }
            else {
                return;
            }

            my $rel_cond = $rel_class->relationship( $key => 'cond' );

            my %search_cond;
            for my $rc ( @$rel_cond ) {
                my $accessor = $rc->[0]->alias || $rc->[0]->name;
                my $f_name   = $rc->[1]->alias || $rc->[1]->name;
                $search_cond{$accessor} = $obj->$f_name;
            }

            my $self_cond = $self->meta->relationship( $method => 'cond' );
            for my $rc ( @$self_cond ) {
                my $accessor = $rc->[0]->alias || $rc->[0]->name;
                my $f_name   = $rc->[1]->alias || $rc->[1]->name;
                $search_cond{$f_name} = $self->$accessor;
            }

            $rel_class->find(\%search_cond)->delete;

            delete $self->rel_value->{$method};
            delete $self->anon_value->{$name};

            $obj->delete;
        }
    );

    $option->{type} = 'many_to_many';
    $class->_relationship_many_to_many->{$class->schema_name}{$name} = $option;
}

sub _get_relationship_condition {
    my ( $class, $klass, $option, $type ) = @_;

    my $rel_cond;
    if( exists $option->{conditions} and ref $option->{conditions} ) {
        $rel_cond = $klass->resolve_condition( $option->{conditions} );
    }
    else {
        my @pkeys = @{ $class->primary_key };
        my $pkey = shift(@pkeys);

        $class->exception("it needs a primary key. ${klass} has none.")
          unless defined $pkey;
        $class->exception( 'it can only for a single primary key' )
          if @pkeys > 0;

        my $fcol;
        if( exists $option->{foreign_key} and defined $option->{foreign_key} ) {
            $fcol = $klass->column( $option->{foreign_key} );
        }
        else {
            $class =~ /([^\:]+)$/;
            my $f_key = lc $1;

            $fcol = $klass->column($f_key)
              || $klass->column( $class->singular_to_plural_func->($f_key) );

            if ( !$fcol and $class->schema_name ne $f_key ) {
                $fcol = $klass->column( $class->schema_name )
                  || $klass->column(
                    $class->singular_to_plural_func->( $class->schema_name ) );
            }

            if ( !$fcol and $type eq 'has_one' ) {
                my @fpkeys = @{ $klass->primary_key };
                my $fpkey  = shift(@fpkeys);
                if ( $fpkey and !@fpkeys and $fpkey eq $pkey ) {
                    $fcol = $klass->$fpkey;
                }
            }
        }

        $fcol || $class->exception(
            "Can't guess foreign column: $class to $klass" );

        $rel_cond = [ [ $class->column($pkey), $fcol ] ];
    }

    return $rel_cond;
}

sub resolve_include {
    my $class    = shift;
    my $struct   = shift;
    my $me_alias = shift;
    my $include  = shift || return;

    my $rel_name;
    my $set_cond;
    my $nest;
    if( ref $include eq 'HASH' ) {
        $rel_name = (keys %$include)[0];
        $nest     = $include->{$rel_name};
    }
    elsif( ref $include eq 'ARRAY' ) {
        $rel_name = $include->[0];
        $set_cond = $include->[1];
    }
    elsif( !ref $include ) {
        $rel_name = $include;
    }
    else {
        $class->exception("unknown include condition: $include");
    }

    my $rel = $class->relationship($rel_name);
    unless( $rel ) {
        $rel = $class->relationship_many_to_many($rel_name)
          || $class->exception(
            'relation ' . $rel_name . ' not found in ' . $class->schema_name );

        my $include_cond;
        if( $nest ) {
            $include_cond = { $rel->{inter_rel_key} => $nest  };
        }
        else {
            $include_cond = $rel->{inter_rel_key};
        }

        return $class->resolve_include(
            $struct,
            $me_alias,
            { $rel->{inter_rel} => $include_cond },
        );
    }

    my $alias_name;
    $alias_name .= $me_alias . '_' if $me_alias;
    $alias_name .= $rel_name;
    return undef if exists $struct->{$alias_name}; ##no critic

    my $cond = $set_cond || do {
        my @rel_cond;
        for my $c ( @{$rel->{cond}} ) {
            my $me = $me_alias ? $c->[0]->table_alias($me_alias) : $c->[0];
            my $foreign = $c->[1];
            push @rel_cond, $me == $foreign->table_alias($alias_name);
        }
        \@rel_cond;
    };

    my $rel_class = $rel->{class_name};

    my @result = (
        {
            include => [
                [ $rel_class->table_name, $alias_name ],
                $cond,
                $rel->{join_type},
            ],
            column => [
                map { $rel_class->column($_)->table_alias($alias_name) }
                  @{ $rel_class->accessors }
            ],
        }
    );

    # nest join
    if( $nest ) {
        my @nest_joins = ref $nest eq 'ARRAY' ? @$nest : ( $nest );
        for my $n (@nest_joins) {
            my @nest_result = $rel_class->resolve_include(
                $struct,
                $alias_name,
                $n,
            );
            push @result, @nest_result;
        }
    }

    if( $me_alias ) {
        $struct->{$alias_name}{$me_alias} = $rel_name;
    }
    else {
        $struct->{$alias_name} = $rel_name;
    }

    return @result;
}



1;
