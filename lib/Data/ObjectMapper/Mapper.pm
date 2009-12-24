package Data::ObjectMapper::Mapper;
use strict;
use warnings;
use Carp::Clan;
use Params::Validate qw(:all);
use Class::MOP;
use Class::MOP::Class;
use Data::ObjectMapper::Utils;

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
};

{
    my %INITIALIZED_CLASSES;

    sub _set_initialized_class {
        my $self = shift;
        {
            no strict 'refs';
            my $pkg = $self->mapped_class;
            *{"$pkg\::__mapper__"} = sub { $self };
        };
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
        from               => undef,
        mapped_class       => undef,
        attributes_config  => +{},
        accessors_config   => +{},
        constructor_config => +{},
        mapped             => 0,
    }, $class;

    unshift @_, 'from';
    splice @_, 2, 0, 'mapped_class';

    my %option = validate(
        @_,
        {   from => {
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

    $self->{from} = $option{from};
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
    for my $meth (qw(from mapped_class attributes_config
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
    my $from  = $self->from;
    my $klass = $self->mapped_class;

    my %option = validate( @_, $OPTIONS_VALIDATE{attributes} );

    my @attributes;
    if( !@{$option{include}} ) { # all
        @attributes = @{ $from->columns };
    }
    else { # ARRAYREF
        for my $p ( @{$option{include}} ) {
            if( $p and ref $p eq $from->column_metaclass ) {
                push @attributes, $p;
            }
            elsif( !ref($p) and my $meta_col = $from->c($p) ) {
                push @attributes, $meta_col;
            }
            else {
                confess "$p is not include metadata at include_property";
            }
        }
    }

    if( $option{exclude} ) {
        my %exclude = map {
              ( ref($_) eq $from->column_metaclass )
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
            $prop->{getter} ||= $prop->{isa}->name;
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
                || $from->c($name)
                || confess "$name : column not found. set property \"isa\". ";

            $option{properties}->{getter} ||= $name;
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
                getter => $attr->name,
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

sub _initialize {
    my $self = shift;

    unless ($self->accessors_config->{auto}
        and $self->constructor_config->{auto} )
    {
        Class::MOP::load_class( $self->mapped_class );
    }

    my $meta;
    if( $self->accessors_config->{auto} ) {
        for my $attr_name ( keys %{$self->attributes_config} ) {
            next if $self->accessors_config->{exclude}->{$attr_name};
            $meta = Class::MOP::Class->create($self->mapped_class);

            if ( $meta->find_all_methods_by_name($attr_name)
                and !$self->accessors_config->{do_replace} )
            {
                # TODO fix english ....
                confess "the $attr_name method already exists."
                    . "use do_replace option or exclude option.";
            }
            else {
                my $attr_config = $self->attributes_config->{$attr_name};
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

                if ( my $meth = $attr_config->{validation_method} ) {
                    $meta->add_before_method_modifier(
                        $attr_name => sub { shift->${meth}(@_) }
                    );
                }
                elsif ( $attr_config->{validation}
                    and my $code = $attr_config->{isa}->validation )
                {
                    $meta->add_before_method_modifier(
                        $attr_name => sub {
                            my $obj = shift;
                            unless ( $code->(@_) ) {
                                confess "parameter $attr_name is not valid.";
                            }
                        }
                    );
                }

            }

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
                my $obj = bless +{}, $class;
                $obj->${_}($param{$_}) for keys %param;
                return $obj;
            }
        );
    }

    if( $meta ) {
        $meta->make_immutable(
            inline_constructor => 0,
            inline_accessors   => 0,
        );
    }

    $self->_set_initialized_class;
}

sub mapping {
    my ( $self, $hashref_data ) = @_;

    my $constructor = $self->constructor_config->{name};
    my $type = $self->constructor_config->{type};

    ## XXX TODO
    ## eager loding
    ## lazy loading
    ## ......

    my %param;
    for my $attr ( keys %{$self->attributes_config} ) {
        my $isa = $self->attributes_config->{$attr}{isa};
        $param{$attr} = $hashref_data->{$isa->name};
    }

    return $self->mapped_class->${constructor}(%param);
}

sub reducing {
    my ( $self, $obj ) = @_;

    my %result;
    for my $attr ( keys %{$self->attributes_config} ) {
        my $getter = $self->attributes_config->{$attr}{getter};
        if( !ref $getter ) {
            $result{$attr} = $obj->$getter;
        }
        elsif( ref $getter eq 'CODE' ) {
            $result{$attr} = $getter->($obj);
        }
        else {
            confess "invalid getter config.";
        }
    }

    return \%result;
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

=head2 reducing


=head1 AUTHOR

Eisuke Oishi

=head1 COPYRIGHT AND LICENSE



