package Data::ObjectMapper::Mapper;
use strict;
use warnings;
use Carp::Clan;

use List::MoreUtils;
use Scalar::Util qw(blessed weaken);
use Digest::MD5 qw(md5_hex);
use Params::Validate qw(:all);
use Class::MOP;
use Class::MOP::Class;
use Log::Any qw($log);

use Data::ObjectMapper::Utils;
use Data::ObjectMapper::Mapper::Instance;
use Data::ObjectMapper::Mapper::Constructor;
use Data::ObjectMapper::Mapper::Accessor;
use Data::ObjectMapper::Mapper::Attribute;

{
    my %INITIALIZED_CLASSES;

    sub _set_initialized_class {
        my $self = shift;
        $INITIALIZED_CLASSES{$self->mapped_class} = 1;
    }

    sub is_initialized {
        my $self = shift;
        my $class = shift;
        return $INITIALIZED_CLASSES{$class};
    }

    sub dissolve {
        my $self = shift;
        delete $INITIALIZED_CLASSES{$self->mapped_class};
        my $meta = $self->mapped_class->meta;
        $meta->make_mutable if $meta->is_immutable;
        $meta->remove_method('__class_mapper__');
        $meta->remove_method('__mapper__');
        $meta->make_immutable(
            inline_constructor => 0,
            inline_accessors   => 0,
        );
    }

    sub DESTROY {
        my $self = shift;
        warn "DESTROY $self" if $ENV{MAPPER_DEBUG};
        delete $INITIALIZED_CLASSES{$self->mapped_class};
    }
};

sub new {
    my $class = shift;

    if( $class->is_initialized($_[1]) ) {
        cluck "$_[1] is already initialized.";
        return $_[1]->__class_mapper__;
    }

    my $self = bless {
        table         => undef,
        mapped_class  => undef,
        attributes    => +{},
        accessors     => +{},
        constructor   => +{},
        mapped        => 0,
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
            default_value     => { type => HASHREF, default => +{} },
            # XXX TODO
            # inherit          => { type => OBJECT, isa => 'Data::ObjectMapper::Mapper' }
        }
    );

    $self->{table} = $option{table};
    $self->{mapped_class} = $option{mapped_class};
    $self->{default_condition} = $option{default_condition};
    $self->{default_value} = $option{default_value};

    $self->_init_constructor_config( %{ $option{constructor} } );
    $self->_init_attributes_config( %{ $option{attributes} } );
    $self->_init_acceesors_config( %{ $option{accessors} } );

    $self->_initialize;
    return $self;
}

sub _init_constructor_config {
    $_[0]->{constructor} = Data::ObjectMapper::Mapper::Constructor->new(@_);
}

sub _init_acceesors_config {
    $_[0]->{accessors} = Data::ObjectMapper::Mapper::Accessor->new(@_);
}

sub _init_attributes_config {
    $_[0]->{attributes} = Data::ObjectMapper::Mapper::Attribute->new(@_);
}

{
    no strict 'refs';
    my $package = __PACKAGE__;
    for my $meth (qw(table mapped_class attributes accessors
                     constructor default_condition default_value)) {
        *{"$package\::$meth"} = sub { $_[0]->{$meth} };
    }
};

sub _initialize {
    my $self = shift;

    unless ($self->accessors->auto and $self->constructor->auto ) {
        Class::MOP::load_class( $self->mapped_class );
    }

    my $meta = Class::MOP::Class->create($self->mapped_class);
    $meta->make_mutable if $meta->is_immutable; ## may be Moose Class

    $meta->add_method( '__class_mapper__' => sub { $self } );

    $meta->add_method(
        '__mapper__' => sub {
            my $instance = shift;
            if( blessed($instance) ){
                Data::ObjectMapper::Mapper::Instance->new( $instance );
            }
        }
    );

    for my $prop_name ( $self->attributes->property_names ) {
        next if $self->accessors->exclude->{$prop_name};
        my $property = $self->attributes->property($prop_name);
        if( $self->accessors->auto ) {
            if ( $meta->find_all_methods_by_name($prop_name)
                and !$self->accessors->do_replace )
            {
                # TODO fix english ....
                confess "the $prop_name method already exists."
                    . "use do_replace option or exclude option.";
            }
            else {
                $meta->add_method (
                    $prop_name => sub {
                        my $obj = shift;
                        if ( @_ ) {
                            my $val = shift;
                            $obj->{$prop_name} = $val;
                        }
                        return $obj->{$prop_name};
                    }
                );
            }
        }

        my $getter = $property->getter || $prop_name;
        my $setter = $property->setter || $prop_name;
        if( $getter eq $setter ) {
            $meta->add_before_method_modifier(
                $getter => sub {
                    my $instance = shift;
                    if( my $mapper = $instance->__mapper__ ) {
                        if( @_ ) {
                            $mapper->set_val_trigger( $prop_name, @_ );
                        }
                        else {
                            $mapper->get_val_trigger( $prop_name );
                        }
                    }
                }
            );
        }
        else {
            $meta->add_before_method_modifier(
                $getter => sub {
                    my $instance = shift;
                    if( my $mapper = $instance->__mapper__ ) {
                        $mapper->get_val_trigger( $prop_name );
                    }
                }
            );

            $meta->add_before_method_modifier(
                $setter => sub {
                    my $instance = shift;
                    if( my $mapper = $instance->__mapper__ ) {
                        $mapper->set_val_trigger( $prop_name, @_ );
                    }
                }
            );
        }
    }

    if( $self->constructor->auto ) {
        $self->constructor->set_arg_type('HASHREF');
        $self->constructor->set_name('new');
        $meta->add_method(
            new => sub {
                my $class = shift;
                my %param = @_ % 2 == 0 ? @_ : %{$_[0]};
                return bless \%param, $class;
            }
        );
    }

    my $destroy = sub {
        my $instance = shift;
        warn "DESTROY $instance" if $ENV{MAPPER_DEBUG};
        if ( blessed($instance)
            and my $mapper = Data::ObjectMapper::Mapper::Instance->get(
                $instance
            )
        ) {
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

    return unless $hashref_data;

    my $constructor = $self->constructor->name;
    my $type = $self->constructor->arg_type;

    my $param;
    for my $prop_name ( $self->attributes->property_names ) {
        my $prop = $self->attributes->property($prop_name);
        my $name = $prop->name || $prop_name;
        my $val = $hashref_data->{$name};
        if( $type eq 'HASH' or $type eq 'HASHREF' ) {
            $param ||= +{};
            $param->{$prop_name} = $val;
        }
        elsif( $type eq 'ARRAY' or $type eq 'ARRAYREF' ) {
            $param ||= +[];
            push @$param, $val;
        }
    }

    return $self->mapped_class->${constructor}(
          $type eq 'HASH' ? %$param
        : ( $type eq 'HASHREF' || $type eq 'ARRAYREF' ) ? $param
        : ( $type eq 'ARRAY' ) ? @$param
        :                        undef
    );
}

sub find {
    my $self = shift;
    my @where = @_;
    my @column;
    for my $prop_name ( $self->attributes->property_names ) {
        my $prop = $self->attributes->property($prop_name);
        next unless $prop->type eq 'column' and !$prop->lazy;
        push @column, $prop->{isa};
    }

    push @where, @{$self->default_condition};
    my $it = $self->table->select->column(@column)->where(@where)->execute;
    return unless $it;
    return $self->mapping($it->next);
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



