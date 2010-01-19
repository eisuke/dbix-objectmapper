package Data::ObjectMapper;
use strict;
use warnings;
use 5.008_001;
our $VERSION = '0.1001';

use Carp::Clan;
use Params::Validate qw(:all);

use Data::ObjectMapper::Log;
use Data::ObjectMapper::Utils;
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
            },
            session_attr => {
                type => HASHREF,
                default => +{},
            },
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
    my %attr = (
        %{$self->{session_attr}},
        @_
    );
    $attr{engine} = $self->engine unless exists $attr{engine};
    return $self->session_class->new(%attr);
}

sub relation {
    my $self = shift;
    my $class = ref($self) || $self;
    my $rel_type = shift;
    my $rel_class
        = $class
        . '::Relation::'
        . Data::ObjectMapper::Utils::camelize($rel_type);
    Class::MOP::load_class($rel_class)
        unless Class::MOP::is_class_loaded($rel_class);
    return $rel_class->new( @_ );
}

1;
__END__

=head1 NAME

Data::ObjectMapper - object-relational mapper and database toolkit.

=head1 DESCRIPTION

Data::ObjectMapper is a object-relational mapper of "Data Mapper Pattern", like Python's SQLAlchemy, and simple interface for database access.

More information of "Data Mapper Pattern" is <http://martinfowler.com/eaaCatalog/dataMapper.html>.

=head1 AUTHOR

Eisuke Oishi

=head1 COPYRIGHT

Copyright 2009 Eisuke Oishi

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

