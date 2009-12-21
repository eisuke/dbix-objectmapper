package Data::ObjectMapper;
use strict;
use warnings;
use Carp::Clan;
use Params::Validate qw(:all);

use Data::ObjectMapper::Mapper;
use Data::ObjectMapper::Session;

my $DEFAULT_MAPPING_CLASS = 'Data::ObjectMapper::Mapper';
my $DEFAULT_SESSION_CLASS = 'Data::ObjectMapper::Session';

# TODO Mapperオブジェクトを作成して、Sessionと同一にする。
#      オブジェクト内にunit_of_workを記録する
#      $mapper = Data::ObjectMapper->new( engine => $engine, meta => $meta );
sub new {
    my $class = shift;

    my %param = validate(
        @_,
        {   engine => { type => OBJECT, isa => 'Data::ObjectMapper::Engine' },
            metadata =>
                { type => OBJECT, isa => 'Data::ObjectMapper::Metadata' },
            class_namespace =>
                { type => SCALAR, optional => 1, default => undef },
            mapping_class => {
                {   type     => SCALAR,
                    optional => 1,
                    isa      => $DEFAULT_MAPPING_CLASS,
                    default  => $DEFAULT_MAPPING_CLASS
                }
            },
            session_class => {
                {   type     => SCALAR,
                    optional => 1,
                    isa      => $DEFAULT_SESSION_CLASS,
                    default  => $DEFAULT_SESSION_CLASS
                }
            }
        }
    );

    return bless \%param, $class;
}

sub metadata      { $_[0]->{metadata} }
sub engine        { $_[0]->{engine} }
sub mapping_class { $_[0]->{mapping_class} }
sub session_class { $_[0]->{session_class} }

#  $mapper->maps( $meta->t('users'), 'Users', { .... } );
sub maps {
    my $self = shift;

    my $metatable = shift;
    my $mapping_class = shift;

    $metatable = $self->metadata->t($metatable) unless ref($metatable);
    my $mapper =$self->mapping_class->new( $metatable => $mapping_class, @_ );
}

sub init_session {
    my $self = shift;
    return $self->session_class->new();
}

1;

__END__

# $mapper->get_class('Users')->new('foo');
# $mapper->get_class('+Other::Class::Users')->new('foo');
sub get_class {
    my $self = shift;
    return unless @_;
    my $name = $self->get_class_name(shift);
    if( $self->mappers->{$name} ) {
        return $name;
    }
    else {
        confess "$name is not mapped.";
    }
}

sub get_class_name {
    my $self = shift;
    my $name = shift || return;

    if( $self->class_namespace ) {
        if( $name =~ /^\+.+/ ) {
            $name =~ s/^\+//;
        }
        else {
            $name = $self->class_namespace . '::' . $name;
        }
    }

    return $name;
}

