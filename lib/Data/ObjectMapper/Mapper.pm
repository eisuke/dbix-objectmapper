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
        exclude    => { type => ARRAYREF, default => +[] },
        do_replace => { type => BOOLEAN,  default => 0 },
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

sub new {
    my $class = shift;

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

    $self->{accessors_config}
        = $self->option_validate( 'accessors', %{ $option{accessors} } );
    $self->{constructor_config}
        = $self->option_validate( 'constructor', %{ $option{constructor} } );
    $self->init_attributes_config( %{ $option{attributes} } );

    return $self;
}

sub option_validate {
    my $self = shift;
    my $type = shift;
    return { validate( @_, $OPTIONS_VALIDATE{$type} ) };
}

{
    no strict 'refs';
    my $package = __PACKAGE__;
    for my $meth (qw(table mapped_class attributes_config accessors_config
            constructor_config mapped )) {
        *{"$package\::$meth"} = sub { $_[0]->{$meth} };
    }
};

my $DEFAULT_ATTRIBUTE_PROPERTY = {
    isa               => undef,
    lazy              => 0,
    validation        => 0,
    getter            => undef,
    validation_method => undef,
};

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
              ( ref($_) eq $table->column_metadata )
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
            $prop->{getter} ||= $isa->name;
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
            $settle_attribute{ $isa->name } = 1;
            $properties{$name}
                = Data::ObjectMapper::Utils::merge_hashref(
                $DEFAULT_ATTRIBUTE_PROPERTY, $option{properties}->{$name},
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

sub mapping {
    my $self = shift;

    my %add_methods;
    my $attribute_generator;
    my $needs_meta = 0;
    my $meta;
    for my $attr_name ( keys %{$self->attributes_config} ) {
        my $attr_config = $self->attributes_config->{$attr_name};

        if( $self->accessors_config->{auto} ) {
            $meta = Class::MOP::Class->create($self->mapped_class);

            if ( $meta->find_all_methods_by_name($attr_name)
                and !$self->accessors_config->{do_replace} )
            {
                # TODO fix english ....
                confess "$attr_name method already exists."
                    . "use do_replace option or exclude option.";
            }
            else {
                $meta->add_method (
                    $attr_name => sub {
                        my $self = shift;
                        if ( @_ ) {
                            my $val = shift;
                            if( my $meth = $attr_config->{validation_method} ) {
                                unless( $self->$meth($val) ) {
                                    confess "XXX validation error";
                                }
                            }
                            elsif ( $attr_config->{validation}
                                and $attr_config->{isa}->validation )
                            {
                                unless (
                                    $attr_config->{isa}->validation->($val) )
                                {
                                    confess "XXX validation error";
                                }
                            }

                            $self->{$attr_name} = $val;
                        }

                        return $self->{$attr_name};
                    }
                );
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
                my $param = @_ == 1 ? $_[0] : { $_[0] };
                my $self = bless $param, $class;
            }
        );
    }

    # XXX set __mepper_meta

    if( $meta ) {
        $meta->make_immutable(
            inline_constructor => 0,
            debug => 1,
        ); # XXXX
    }

    # attributes => {
    #     isa
    #     lazy
    #     validation
    #     getter
    #     validation_method
    # },
    # accessors => {
    #     auto
    #     exclude
    #     do_replace
    # },
    # constructor => {
    #     auto
    # }
}



1;

__END__

