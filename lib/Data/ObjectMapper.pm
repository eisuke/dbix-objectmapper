package Data::ObjectMapper;
use strict;
use warnings;
use Carp::Clan;
use Params::Validate qw(:all);

use Data::ObjectMapper::Mapper;

my $DEFAULT_MAPPING_CLASS = 'Data::ObjectMapper::Mapper';

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
            }
        }
    );

    $param{mapped_classes} = +[];
    $param{mappers}        = +{};

    return bless \%param, $class;
}


# $mapper->metadata->t('users');
# my $query = $mapper->metadata->select()->from('users')->where()->limit;
sub metadata        { $_[0]->{metadata} }
sub engine          { $_[0]->{engine} }
sub class_namespace { $_[0]->{class_namespace} }
sub mapping_class   { $_[0]->{mapping_class} }
sub mapped_classes  { $_[0]->{mapped_classes} }
sub mappers         { $_[0]->{mappers} }

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

#  $mapper->maps( $meta->t('users'), 'Users', { .... } );
sub maps {
    my $self = shift;

    my $metatable = shift;
    my $mapping_class = shift;
    $mapping_class = $self->get_class_name($mapping_class);

    confess "$mapping_class is already mapped."
        if $self->mapped_classes->{$mapping_class};

    $metatable = $self->metadata->t($metatable) unless ref($metatable);
    my $mapper =$self->mapping_class->new( $metatable => $mapping_class, @_ );
    $mapper->mapping;

    $self->{mappers}{$mapping_class} = $mapper;
    push @{$self->mapperd_classes}, $mapping_class;
}

# my $user = $mapper->find( Users => 1 );
sub find {
    my $self = shift;
    my ( $klass, $id ) = @_;

    my $mapper = $self->mappers->{$klass} || confess "$klass is not mapped";

}

# $mapper->all('Users' => 'UserAddress')->filter( )->group_by( )->limit->offset->pager;
sub all  {}

# User->new({ name => 'hoge' });
# $mapper->save($user);
sub save {}

1;
