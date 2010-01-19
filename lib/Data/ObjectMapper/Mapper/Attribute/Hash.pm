package Data::ObjectMapper::Mapper::Attribute::Hash;
use strict;
use warnings;
use Carp::Clan;
use base qw(Data::ObjectMapper::Mapper::Attribute);
use Data::ObjectMapper::Mapper::Attribute::Property;

sub init {
    my $self = shift;

    my $table = $self->table;
    my @attributes = $self->_init_attributes();

    my %properties;
    my %settle_property;

    for my $name ( keys %{ $self->properties } ) {
        my $isa
            = $self->properties->{$name}{isa}
                || $table->c($name)
                || confess "$name : column not found. set property \"isa\". ";

        $self->properties->{$name}{getter} ||= $self->prefix . $name;
        $self->properties->{$name}{setter} ||= $self->prefix . $name;

        if( ref($isa) eq 'Data::ObjectMapper::Metadata::Table::Column' ) {
            $settle_property{ $isa->name } = 1;
        }
        else {
            $isa->name($name);
        }

        $self->properties->{$name}{isa} = $isa;

        $properties{$name}
            = Data::ObjectMapper::Mapper::Attribute::Property->new(
            %{ $self->properties->{$name} }
        );
    }

    for my $attr (@attributes) {
        next if $settle_property{ $attr->name };
        $properties{ $attr->name }
            = Data::ObjectMapper::Mapper::Attribute::Property->new(
            isa    => $attr,
            getter => $self->prefix . $attr->name,
            setter => $self->prefix . $attr->name,
            );
        $settle_property{ $attr->name } = 1;
    }

    if ( $self->prefix ) {
        %properties = map { $self->prefix . $_ => $properties{$_} }
            keys %properties;
    }

    $self->{properties} = \%properties;
}

sub _init_attributes {
    my $self = shift;
    my $table = $self->table;
    my %primary_key_map = map { $_ => $table->c($_) } @{ $table->primary_key };

    my @attributes;
    if ( my @include = @{ $self->include } ) {
        my $ex_primary_key = 0;
        for my $p ( @include ) {
            if ( $p and ref $p eq $table->column_metaclass ) {
                $ex_primary_key = 1 if $primary_key_map{ $p->name };
                push @attributes, $p;
            }
            elsif ( !ref($p) and my $meta_col = $table->c($p) ) {
                $ex_primary_key = 1
                    if $primary_key_map{ $meta_col->name };
                push @attributes, $meta_col;
            }
            else {
                confess "$p is not exists metadata at include_property";
            }
        }

        unless ($ex_primary_key) {
            push( @attributes, $_ ) for values %primary_key_map;
        }
    }
    else {    # default all
        @attributes = @{ $table->columns };
    }

    if ( @{$self->exclude} ) {
        my %exclude = map {
            ( ref($_) eq $table->column_metaclass )
          ? ( $_->name => 1 )
          : ( $_ => 1 );
        } grep {
            if ($_) {
                if ( ref($_) eq $table->column_metaclass ) {
                    !$primary_key_map{ $_->name };
                }
                else {
                    !$primary_key_map{$_};
                }
            }
        } @{ $self->exclude };
        @attributes = grep { !$exclude{ $_->name } } @attributes;
    }

    return @attributes;
}

sub property_names { keys %{ $_[0]->{properties} } }
sub property       { $_[0]->{properties}->{ $_[1] } }

1;

