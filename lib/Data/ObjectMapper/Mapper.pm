package Data::ObjectMapper::Mapper;
use strict;
use warnings;
use Carp::Clan;
use Params::Validate qw(:all);
use Scalar::Util;
use Class::MOP;
use Class::MOP::Class;
use Data::ObjectMapper::Utils;

## TODO generete argument structure from feched data
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
    my %MAPPED_CLASSES;

    sub _regist_mapped_class {
        my $self = shift;
        $MAPPED_CLASSES{$self->mapped_class} = $self;
    }

    sub is_mapped {
        my $self = shift;
        my $class = shift;
        return $MAPPED_CLASSES{$class};
    }
};

sub new {
    my $class = shift;

    if( my $mapped_class = $class->is_mapped( $_[1]) ) {
        cluck "$_[1] is already mapped. this return the mapped object.";
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

    $self->init_attributes_config( %{ $option{attributes} } );
    $self->init_acceesors_config( %{ $option{accessors} } );
    $self->init_constructor_config( %{ $option{constructor} } );

    $self->mapping;
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

sub init_constructor_config {
    my $self = shift;
    my %option = validate( @_, $OPTIONS_VALIDATE{constructor} );
    $self->{constructor_config} = \%option;
}

sub init_acceesors_config {
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

sub init_attributes_config {
    my $self = shift;
    my $table = $self->table;
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
    else { # HASH
        my %properties;
        my %settle_attribute;

        for my $name ( keys %{ $option{properties} } ) {
            my $isa
                = $option{properties}->{isa}
                || $table->c($name)
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

sub mapping {
    my $self = shift;

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
            debug => 1,
        ); # XXXX
    }
    elsif( !Class::MOP::is_class_loaded($self->mapped_class) ) {
        Class::MOP::load_class($self->mapped_class);
    }

    {
        no strict 'refs';
        my $pkg = $self->mapped_class;
        *{"$pkg\::__mapper__"} = sub { $self };
    };

    $self->_regist_mapped_class;
}

1;

__END__

