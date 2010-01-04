package Data::ObjectMapper::Mapper::Attribute::Property;
use strict;
use warnings;
use Carp::Clan;
use Params::Validate qw(:all);

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

sub isa               { $_[0]->{isa} }
sub lazy              { $_[0]->{lazy} }
sub validation        { $_[0]->{validation} }
sub validation_method { $_[0]->{validation_method} }
sub getter            { $_[0]->{getter} }
sub setter            { $_[0]->{setter} }

1;
