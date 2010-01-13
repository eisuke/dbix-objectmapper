package Data::ObjectMapper::Mapper::Attribute::Property;
use strict;
use warnings;
use Carp::Clan;
use Params::Validate qw(:all);

my @TYPES = qw(column relation);

sub new {
    my $class = shift;

    my %prop = validate(
        @_,
        {
            isa        => +{
                type => OBJECT,
                callbacks => {
                    check_duck_type => sub {
                        $_[0]->can('name') && $_[0]->can('validation');
                    }
                }
            },
            lazy       => +{ type => BOOLEAN, default => 0 },
            validation => +{ type => BOOLEAN, default => 0 },
            validation_method => +{
                type    => CODEREF,
                default => sub { }
            },
            getter => +{ type => SCALAR },
            setter => +{ type => SCALAR },
        }
    );

    bless \%prop, $class;
}

sub lazy              { $_[0]->{lazy} }
sub validation_method { $_[0]->{validation_method} }
sub getter            { $_[0]->{getter} }
sub setter            { $_[0]->{setter} }

## proxy

sub type {
    my $self = shift;

    if( $self->{isa}->isa('Data::ObjectMapper::Metadata::Table::Column') ) {
        return 'column';
    }
    elsif( $self->{isa}->isa('Data::ObjectMapper::Relation') ) {
        return 'relation';
    }

    return 0;
}

sub validation {
    my $self = shift;
    return $self->{isa}->validation if $self->{validation};
    return;
}

sub name {
    my $self = shift;

    if( $self->type eq 'column' ) {
        return $self->{isa}->name;
    }

}

sub get {
    my $self = shift;
    if( $self->type eq 'relation' ) {
        return $self->{isa}->get(@_);
    }

    return;
}

sub mapping {
    my $self = shift;
    if( $self->type eq 'relation' ) {
        return $self->{isa}->mapping(@_);
    }

    return;
}

sub table {
    my $self = shift;

    if( $self->type eq 'relation' ) {
        return $self->{isa}->table;
    }

    return;
}

sub mapper {
    my $self = shift;
    if( $self->type eq 'relation' ) {
        return $self->{isa}->mapper;
    }
    return;
}

sub relation_condition {
    my $self = shift;

    if( $self->type eq 'relation' ) {
        return $self->{isa}->relation_condition(@_);
    }

    return;
}

sub is_multi {
    my $self = shift;

    if( $self->type eq 'relation' ) {
        return $self->{isa}->is_multi;
    }

    return;
}

1;
