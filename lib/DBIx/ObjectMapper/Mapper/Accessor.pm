package DBIx::ObjectMapper::Mapper::Accessor;
use strict;
use warnings;
use Carp::Clan;
use Params::Validate qw(:all);

sub new {
    my $class  = shift;
    my $mapper = shift;

    my %option = validate(
        @_,
        {   auto => { type => BOOLEAN, default => 0 },
            exclude =>
                { type => ARRAYREF, default => +[], depends => 'auto' },
            do_replace =>
                { type => BOOLEAN, default => 0, depends => 'auto' },
            generic_getter => { type => SCALAR, default => q{} },
            generic_setter => { type => SCALAR, default => q{} },
        }
    );

    if ( $option{exclude} ) {
        for my $ex ( @{ $option{exclude} } ) {
            # XXX fixed English
            confess "Can't exlude $ex. not included attributes."
                unless $mapper->attributes->property($ex);
        }
    }

    $option{exclude} = +{ map { $_ => 1 } @{ $option{exclude} } };

    return bless \%option, $class;
}

sub auto           { $_[0]->{auto} }
sub exclude        { $_[0]->{exclude} }
sub do_replace     { $_[0]->{do_replace} }
sub generic_setter { $_[0]->{generic_setter} }
sub generic_getter { $_[0]->{generic_getter} }

1;
