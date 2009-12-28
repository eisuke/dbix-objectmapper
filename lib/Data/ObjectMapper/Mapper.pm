package Data::ObjectMapper::Mapper;
use strict;
use warnings;
use Scalar::Util qw(blessed);
use Digest::MD5 qw(md5_hex);
use Carp::Clan;
use Params::Validate qw(:all);
use Class::MOP;
use Class::MOP::Class;
use Data::ObjectMapper::Utils;
use Data::ObjectMapper::Mapper::Instance;

my @CONSTRUCTOR_ARGUMENT_TYPES = qw( HASHREF HASH ARRAYREF ARRAY );

my %OPTIONS_VALIDATE = (
    attributes => {
        include    => { type => ARRAYREF, default => +[] },
        exclude    => { type => ARRAYREF, default => +[] },
        prefix     => { type => SCALAR,   default => q{} },
        properties => { type => HASHREF|ARRAYREF,  default => +{} },
    },
    accessors => {
        auto       => { type => BOOLEAN,  default => 0 },
        exclude    => { type => ARRAYREF, default => +[], depends => 'auto' },
        do_replace => { type => BOOLEAN,  default => 0, depends => 'auto' },
    },
    constructor => {
        name     => { type => SCALAR, default => 'new' },
        arg_type => {
            type      => SCALAR,
            default   => 'HASHREF',
            callbacks => {
                valid_arg => sub {
                    grep { $_[0] eq $_ } @CONSTRUCTOR_ARGUMENT_TYPES;
                }
            }
        },
        auto => { type => BOOLEAN, default => 0 },
    },
);

my $DEFAULT_ATTRIBUTE_PROPERTY = {
    isa               => undef,
    lazy              => 0,
    validation        => 0,
    validation_method => undef,
    getter            => undef,
    setter            => undef,
};

{
    my %INITIALIZED_CLASSES;

    sub _set_initialized_class {
        my $self = shift;
        $INITIALIZED_CLASSES{$self->mapped_class} = $self;
    }

    sub is_initialized {
        my $self = shift;
        my $class = shift;
        return $INITIALIZED_CLASSES{$class};
    }
};

sub new {
    my $class = shift;

    if( my $mapped_class = $class->is_initialized( $_[1]) ) {
        cluck "$_[1] is already initialized.";
        return $mapped_class;
    }

    my $self = bless {
        table              => undef,
        mapped_class       => undef,
        attributes_config  => +{},
        accessors_config   => +{},
        constructor_config => +{},
        mapped             => 0,
    }, $class;

    unshift @_, 'table';
    splice @_, 2, 0, 'mapped_class';

    my %option = validate(
        @_,
        {   table => {
                type => OBJECT,
                # XXXX not only table
                isa  => 'Data::ObjectMapper::Metadata::Table'
            },
            mapped_class      => { type => SCALAR, },
            attributes        => { type => HASHREF, default => +{} },
            accessors         => { type => HASHREF, default => +{} },
            constructor       => { type => HASHREF, default => +{} },
            default_condition => { type => ARRAYREF, default => +[] },
        }
    );

    $self->{table} = $option{table};
    $self->{mapped_class} = $option{mapped_class};

    $self->_init_attributes_config( %{ $option{attributes} } );
    $self->_init_acceesors_config( %{ $option{accessors} } );
    $self->_init_constructor_config( %{ $option{constructor} } );

    $self->_initialize;
    return $self;
}

{
    no strict 'refs';
    my $package = __PACKAGE__;
    for my $meth (qw(table mapped_class attributes_config
                     accessors_config constructor_config)) {
        *{"$package\::$meth"} = sub { $_[0]->{$meth} };
    }
};

sub _init_constructor_config {
    my $self = shift;
    my %option = validate( @_, $OPTIONS_VALIDATE{constructor} );
    $self->{constructor_config} = \%option;
}

sub _init_acceesors_config {
    my $self = shift;

    my %option = validate( @_, $OPTIONS_VALIDATE{accessors} );
    if( $option{exclude} ) {
        for my $ex ( @{$option{exclude}}) {
            # XXX fixed English
            confess "Can't exlude $ex. not included attributes."
                unless $self->attributes_config->{$ex};
        }
    }
    $option{exclude} = +{ map { $_ => 1 } @{ $option{exclude} } };
    $self->{accessors_config} = \%option;
}

sub _init_attributes_config {
    my $self = shift;
    my $table  = $self->table;
    my $klass = $self->mapped_class;

    my %option = validate( @_, $OPTIONS_VALIDATE{attributes} );

    my @attributes;
    if( !@{$option{include}} ) { # all
        @attributes = @{ $table->columns };
    }
    else { # ARRAYREF
        for my $p ( @{$option{include}} ) {
            if( $p and ref $p eq $table->column_metaclass ) {
                push @attributes, $p;
            }
            elsif( !ref($p) and my $meta_col = $table->c($p) ) {
                push @attributes, $meta_col;
            }
            else {
                confess "$p is not include metadata at include_property";
            }
        }
    }

    if( $option{exclude} ) {
        my %exclude = map {
              ( ref($_) eq $table->column_metaclass )
            ? ( $_->name => 1 )
            : ( $_ => 1 );
        } grep { $_ } @{ $option{exclude} };
        @attributes = grep { !$exclude{ $_->name } } @attributes;
    }

    if( ref $option{properties} eq 'ARRAY' ) {
        if (   $self->constructor_config->{arg_type} eq 'ARRAY'
            || $self->constructor_config->{arg_type} eq 'ARRAYREF' )
        {
            confess "not match constructor{arg_type}.(properties is HASHREF)";
        }

        my %settle_attribute;
        my @properties;
        for my $prop ( @{ $option{properties} } ) {
            my $isa = $prop->{isa} || confess "set property \"isa\". ";
            $prop->{getter} ||= $option{prefix} . $prop->{isa}->name;
            $prop->{setter} ||= $option{prefix} . $prop->{isa}->name;
            push @properties,
                Data::ObjectMapper::Utils::merge_hashref(
                    $DEFAULT_ATTRIBUTE_PROPERTY, $prop,
                );

            $settle_attribute{ $isa->name } = 1;
            # XXXX TODO RELATION, SELECT, ETC...
        }

        $self->{attributes_config} = \@properties;
    }
    else { # HASH or auto
        my %properties;
        my %settle_attribute;

        for my $name ( keys %{ $option{properties} } ) {
            my $isa
                = $option{properties}->{isa}
                || $table->c($name)
                || confess "$name : column not found. set property \"isa\". ";

            $option{properties}->{getter} ||= $option{prefix} . $name;
            $option{properties}->{setter} ||= $option{prefix} . $name;
            $settle_attribute{ $isa->name } = 1;
            $properties{$name} = Data::ObjectMapper::Utils::merge_hashref(
                $DEFAULT_ATTRIBUTE_PROPERTY,
                $option{properties}->{$name},
            );

            # XXXX TODO RELATION, SELECT, ETC...
        }

        for my $attr (@attributes) {
            next if $settle_attribute{ $attr->name };
            $properties{ $attr->name } = {
                %$DEFAULT_ATTRIBUTE_PROPERTY,
                isa    => $attr,
                getter => $option{prefix} . $attr->name,
                setter => $option{prefix} . $attr->name,
            };
            $settle_attribute{ $attr->name } = 1;
        }

        if ( $option{prefix} ) {
            %properties = map { $option{prefix} . $_ => $properties{$_} }
                keys %properties;
        }

        $self->{attributes_config} = \%properties;
    }
}

sub get_attributes_name {
    my $self = shift;
    return
        ref( $self->attributes_config ) eq 'HASH'
        ? keys %{ $self->attributes_config }
        : @{ $self->attributes_config };
}

sub get_attribute {
    my ($self, $name) = @_;

    if( ref( $self->attributes_config ) eq 'HASH' ) {
        $self->attributes_config->{$name};
    }
    else {
        return grep{ $_->{isa}->name eq $name } @{$self->attributes_config};
    }
}

sub _initialize {
    my $self = shift;

    unless ($self->accessors_config->{auto}
        and $self->constructor_config->{auto} )
    {
        Class::MOP::load_class( $self->mapped_class );
    }

    my $meta = Class::MOP::Class->create($self->mapped_class);
    $meta->make_mutable if $meta->is_immutable;

    $meta->add_method(
        '__mapper__' => sub {
            my $instance = shift;
            if( blessed($instance) ){
                Data::ObjectMapper::Mapper::Instance->new(
                    $self,
                    $instance,
                );
            }
            else {
                $self;
            }
        }
    );

    for my $attr_name ( $self->get_attributes_name ) {
        next if $self->accessors_config->{exclude}->{$attr_name};
        my $attr_config = $self->get_attribute($attr_name);
        if( $self->accessors_config->{auto} ) {
            if ( $meta->find_all_methods_by_name($attr_name)
                and !$self->accessors_config->{do_replace} )
            {
                # TODO fix english ....
                confess "the $attr_name method already exists."
                    . "use do_replace option or exclude option.";
            }
            else {
                $meta->add_method (
                    $attr_name => sub {
                        my $obj = shift;
                        if ( @_ ) {
                            my $val = shift;
                            $obj->{$attr_name} = $val;
                        }
                        return $obj->{$attr_name};
                    }
                );
            }
        }

        my $getter = $attr_config->{getter} || $attr_name;
        my $setter = $attr_config->{setter} || $attr_name;
        if( $getter eq $setter ) {
            $meta->add_before_method_modifier(
                $getter => sub {
                    my $instance = shift;
                    my $mapper = $instance->__mapper__;
                    if( @_ ) {
                        $mapper->set_val_trigger( $attr_name, @_ );
                    }
                    else {
                        $mapper->get_val_trigger( $attr_name );
                    }
                }
            );
        }
        else {
            $meta->add_before_method_modifier(
                $getter => sub {
                    my $instance = shift;
                    $instance->__mapper__->get_val_trigger( $attr_name );
                }
            );

            $meta->add_before_method_modifier(
                $setter => sub {
                    my $instance = shift;
                    $instance->__mapper__->set_val_trigger( $attr_name, @_ );
                }
            );
        }
    }

    if( $self->constructor_config->{auto} ) {
        $self->constructor_config->{arg_type} = 'HASHREF';
        $self->constructor_config->{name} = 'new';
        $meta ||= Class::MOP::Class->create($self->mapped_class);
        $meta->add_method(
            new => sub {
                my $class = shift;
                my %param = @_ % 2 == 0 ? @_ : %{$_[0]};
                my $obj = bless \%param, $class;
                return $obj;
            }
        );
    }

    my $destroy = sub {
        my $instance = shift;
        warn "$instance DESTROY" if $ENV{DOM_CHECK_DESTROY};
        if ( my $mapper
            = Data::ObjectMapper::Mapper::Instance->get($instance) )
        {
            $mapper->demolish;
        }
    };

    if ( $meta->find_all_methods_by_name('DESTROY') ) {
        $meta->add_after_method_modifier('DESTROY' => $destroy );
    }
    else {
        $meta->add_method( 'DESTROY' => $destroy );
    }

    $meta->make_immutable(
        inline_constructor => 0,
        inline_accessors   => 0,
    ); # XXXX Moose?

    $self->_set_initialized_class;
}

sub mapping {
    my ( $self, $hashref_data ) = @_;

    my $constructor = $self->constructor_config->{name};
    my $type = $self->constructor_config->{arg_type};
    ## XXX TODO
    ## eager loding
    ## lazy loading
    ## ......

    my $param;
    for my $attr ( $self->get_attributes_name ) {
        my $isa = $self->get_attribute($attr)->{isa};
        if( $type eq 'HASH' or $type eq 'HASHREF' ) {
            $param ||= +{};
            $param->{$attr} = $hashref_data->{$isa->name};
        }
        elsif( $type eq 'ARRAY' or $type eq 'ARRAYREF' ) {
            $param ||= +[];
            push @$param, $hashref_data->{$isa->name};
        }
    }

    return $self->mapped_class ->${constructor}(
          $type eq 'HASH' ? %$param
        : ( $type eq 'HASHREF' || $type eq 'ARRAYREF' ) ? $param
        : ( $type eq 'ARRAY' ) ? @$param
        :                        undef
    );
}

sub find {
    my $self = shift;
    return $self->mapping( $self->table->_find(@_) );
}

sub get_unique_condition {
    my ( $self, $id ) = @_;
    my ( $type, @cond ) = $self->table->get_unique_condition($id);
    confess "condition is not unique." unless @cond;
    return $self->create_cache_key($type, @cond), @cond;
}

sub create_cache_key {
    my ( $self, $cond_type, @cond ) = @_;
    my $key
        = $cond_type
        ? $cond_type . '#'
            . join( '&', map { $_->[0]->name . '=' . $_->[2] } @cond )
        : join( '&', map { $_->[0]->name . '=' . $_->[2] } @cond );

    return md5_hex( $self->mapped_class . '@' . $key );
}

sub primary_cache_key {
    my ( $self, $result ) = @_;

    my @ids;
    for my $key ( @{ $self->table->primary_key } ) {
        push @ids,
            $key . '='
            . ( defined $result->{$key} ? $result->{$key} : 'NULL' );
    }

    return md5_hex( $self->mapped_class . '@' . join( '&', @ids ) );
}

sub unique_cache_keys {
    my ( $self, $result ) = @_;
    my @keys;
    for my $uniq ( @{ $self->table->unique_key } ) {
        my $name = $uniq->[0];
        my $keys = $uniq->[1];
        my @uniq_ids;
        for my $key (@$keys) {
            push @uniq_ids,
                $key . '='
                . ( defined $result->{$key} ? $result->{$key} : 'NULL' );
        }
        push @keys,
            md5_hex( $self->mapped_class . '@'
                . $name . '#'
                . join( '&', @uniq_ids ) );
    }

    return @keys;
}


1;

__END__

=head1 NAME

Data::ObjectMapper::Mapper

=head1 DESCRIPTION

=head1 SYNOPSIS

  my $mapped_artist = Data::ObjectMapper::Mapper->new(
     $meta->t('artist') => 'My::Artist',
     attributes => {
         include    => [],
         exclude    => [],
         prefix     => '',
         properties => +{
             isa               => undef,
             lazy              => 0,
             validation        => 0,
             validation_method => undef,
         }
     },
     accessors => +{
         auto       => 0,
         exclude    => [],
         do_replace => 0,
     },
     constructor => +{
         name     => 'new',
         arg_type => 'HASHREF',
         auto     => 0,
     },
     default_condition => [

     ],
 );

=head1 METHODS

=head2 new

B<<Options>>

=head3 attributes

=head4  include

    => { type => ARRAYREF, default => +[] },

=head4  exclude

    => { type => ARRAYREF, default => +[] },

=head4 prefix

     => { type => SCALAR,   default => q{} },

=head4  properties

 => { type => HASHREF|ARRAYREF,  default => +{} },

=over 5

=item isa

               => undef,

=item lazy

              => 0,

=item validation

        => 0,

=item validation_method

 => undef,

=item getter

            => undef,

=item setter

            => undef,

=back

=head3

=head4 auto

       => { type => BOOLEAN,  default => 0 },

=head4 exclude

    => { type => ARRAYREF, default => +[], depends => 'auto' },

=head4 do_replace

 => { type => BOOLEAN,  default => 0, depends => 'auto' },

=head3 constructor

=head4 name

     => { type => SCALAR, default => 'new' },

=head4 arg_type

@CONSTRUCTOR_ARGUMENT_TYPES;

=head4 auto

 => { type => BOOLEAN, default => 0 },


=head3 default_condition


=head2 is_initialized

=head2 mapping

=head1 AUTHOR

Eisuke Oishi

=head1 COPYRIGHT AND LICENSE



