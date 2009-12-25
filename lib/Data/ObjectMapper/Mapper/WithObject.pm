package Data::ObjectMapper::Mapper::WithInstance;
use strict;
use warnings;
use Carp::Clan;
use Digest::MD5 qw(md5_hex);

sub new {
    my ( $class, $mapper, $instance ) = @_;
    bless { mapper => $mapper, instance => $instance }, $class;
}

sub mapper   { $_[0]->{mapper} }
sub instance { $_[0]->{instance} }

sub reducing {
    my ( $self ) = @_;

    my %result;
    for my $attr ( keys %{$self->mapper->attributes_config} ) {
        my $getter = $self->mapper->attributes_config->{$attr}{getter};
        if( !ref $getter ) {
            $result{$attr} = $self->instance->$getter;
        }
        elsif( ref $getter eq 'CODE' ) {
            $result{$attr} = $getter->($self->instance);
        }
        else {
            confess "invalid getter config.";
        }
    }

    return \%result;
}

sub cache_keys {
    my $self = shift;
    my $result = shift || $self->reducing;
    return (
        $self->primary_cache_key($result),
        $self->unique_cache_keys($result),
    );
}

sub primary_cache_key {
    my ( $self, $result ) = @_;

    my @ids;
    for my $key ( @{ $self->mapper->from->primary_key } ) {
        push @ids,
            $key . '=' . ( defined $result->{$key} ? $result->{$key} : 'NULL' );
    }

    return md5_hex( $self->mapper->mapped_class . '@' . join( '&', @ids ) );
}

sub primary_cache_key_from_instance {
    my $self = shift;
    my $cond = $self->identity_condition;
    return $self->mapper->create_cache_key( undef, @$cond );
}

sub unique_cache_keys {
    my ( $self, $result ) = @_;
    my $mapper = $self->mapper;
    my @keys;
    for my $uniq ( @{ $mapper->from->unique_key } ) {
        my $name = $uniq->[0];
        my $keys = $uniq->[1];
        my @uniq_ids;
        for my $key (@$keys) {
            push @uniq_ids,
                $key . '='
                . ( defined $result->{$key} ? $result->{$key} : 'NULL' );
        }
        push @keys,  md5_hex( $mapper->mapped_class . '@' . $name . '#' . join( '&', @uniq_ids ) );
    }

    return @keys;
}

sub identity_condition {
    my $self = shift;
    my $record = shift || $self->reducing;
    return +[ map { $self->mapper->from->c($_) == $record->{$_} }
            @{ $self->mapper->from->primary_key } ];
}

sub reflesh {
    my $self = shift;
    $self->modify( $self->from->_find(@_) );
}

sub modifiy {
    my $self = shift;
    my $rdata = shift;

    for my $attr ( keys %{ $self->mapper->attributes_config } ) {
        my $setter = $self->mapper->attributes_config->{$attr}{setter};
        if ( !ref $setter ) {
            $self->instance->$setter( $rdata->{$attr} );
        }
        elsif ( ref $setter eq 'CODE' ) {
            $setter->( $self->instance, $rdata->{$attr} );
        }
        else {
            confess "invalid setter config.";
        }
    }

    return $self->instance;
}

1;
