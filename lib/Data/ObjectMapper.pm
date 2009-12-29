package Data::ObjectMapper;
use strict;
use warnings;
use Carp::Clan;
use Params::Validate qw(:all);

use Data::ObjectMapper::Metadata;
use Data::ObjectMapper::Mapper;
use Data::ObjectMapper::Session;

my $DEFAULT_MAPPING_CLASS = 'Data::ObjectMapper::Mapper';
my $DEFAULT_SESSION_CLASS = 'Data::ObjectMapper::Session';

sub new {
    my $class = shift;
    my %param_tmp = @_;

    my %param = validate(
        @_,
        {   engine => { type => OBJECT, isa => 'Data::ObjectMapper::Engine' },
            metadata => {
                type => OBJECT,
                isa => 'Data::ObjectMapper::Metadata',
                default => Data::ObjectMapper::Metadata->new(),
            },
            mapping_class => {
                type     => SCALAR,
                isa      => $DEFAULT_MAPPING_CLASS,
                default  => $DEFAULT_MAPPING_CLASS,
            },
            session_class => {
                type     => SCALAR,
                isa      => $DEFAULT_SESSION_CLASS,
                default  => $DEFAULT_SESSION_CLASS,
            }
        }
    );

    $param{metadata}->engine($param{engine});

    return bless \%param, $class;
}

sub metadata      { $_[0]->{metadata} }
sub engine        { $_[0]->{engine} }
sub mapping_class { $_[0]->{mapping_class} }
sub session_class { $_[0]->{session_class} }

sub maps {
    my $self = shift;

    my $metatable = shift;
    my $mapping_class = shift;

    $metatable = $self->metadata->t($metatable) unless ref($metatable);
    my $mapper = $self->mapping_class->new( $metatable => $mapping_class, @_ );
}

sub begin_session {
    my $self = shift;
    my %attr = @_;
    $attr{engine} = $self->engine unless exists $attr{engine};
    return $self->session_class->new(%attr);
}

1;

__END__
