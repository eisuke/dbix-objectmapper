package Data::ObjectMapper::Mapper::Attribute::Array;
use strict;
use warnings;
use Carp::Clan;
use base qw(Data::ObjectMapper::Mapper::Attribute);
use Data::ObjectMapper::Mapper::Attribute::Property;

sub init {
    my $self = shift;

    my %settle_attribute;
    my @properties;
    for my $prop ( @{$self->properties} ) {
        my $isa = $prop->{isa} || confess "set property \"isa\". ";
        $prop->{getter} ||= $self->prefix . $prop->{isa}->name;
        $prop->{setter} ||= $self->prefix . $prop->{isa}->name;
        push @properties,
            Data::ObjectMapper::Mapper::Attribute::Property->new(%$prop);
        $settle_attribute{ $isa->name } = 1;
    }

    confess "primary key must be included in property"
        if List::MoreUtils::notall { $settle_attribute{$_} }
        @{ $self->table->primary_key };

    $self->{properties} = \@properties;
}

sub property_names { map { $_->name } @{ $_[0]->properties } }

sub property {
    my ($self, $name) = @_;
    for( @{ $self->properties } ) {
        return $_ if $_->name eq $name;
    }
    return;
}

1;
