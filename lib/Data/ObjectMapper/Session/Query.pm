package Data::ObjectMapper::Session::Query;
use strict;
use warnings;
use Carp::Clan;
use Scalar::Util qw(refaddr);
use Clone qw(clone);
use Digest::MD5 qw(md5_hex);

sub new {
    my ( $class, $target_class ) = @_;
    bless {
        target_class => $target_class,
        cache        => +{},
        persistent   => +{},
        detached     => +{},
        identity_map => +{},
    }, $class;
}

sub target_class { $_[0]->{target_class} }

sub is_persistent {
    my ( $self, $obj ) = @_;
    $self->{persistent}{refaddr($obj)};
}

sub get_identity_condition {
    my ( $self, $obj ) = @_;
    $self->{identity_map}{refaddr($obj)};
}

sub get_original_data {
    my ( $self, $obj ) = @_;
    my $uniq_cond = $self->get_identity_condition($obj) || return;
    return $self->_get_cache(undef, @$uniq_cond);
}

sub detach {
    my ( $self, $obj, $reduced_data ) = @_;
    my $id = refaddr($obj);
    delete $self->{persistent}{$id};
    $self->{detached}{$id} = 1;
    $reduced_data ||= $obj->__mapper__->reducing($obj);
    $self->_clear_cache($reduced_data);
}

sub is_detached {
    my ( $self, $obj ) = @_;
    $self->{detached}{refaddr($obj)};
}

sub attach {
    my ( $self, $obj, $record ) = @_;
    my $mapper = $obj->__mapper__;
    $record ||= $obj->__mapper__->reducing($obj);
    my $addr = refaddr($obj);
    $self->{persistent}{$addr} = 1;
    $self->{identity_map}{$addr} = +[
        map { $mapper->from->c($_) == $record->{$_} }
            @{ $mapper->from->primary_key }
    ];
}

sub all {

}

sub _get_cache {
    my ( $self, $cond_type, @cond ) = @_;
    my $key
        = $cond_type
        ? $cond_type . '#'
            . join( '&', map { $_->[0]->name . '=' . $_->[2] } @cond )
        : join( '&', map { $_->[0]->name . '=' . $_->[2] } @cond );

    return $self->{cache}{md5_hex($key)};
}

sub _get_primary_cache_key {
    my ( $self, $result ) = @_;

    my $mapper = $self->target_class->__mapper__;
    my @ids;
    for my $key ( @{ $mapper->from->primary_key } ) {
        push @ids,
            $key . '=' . ( defined $result->{$key} ? $result->{$key} : 'NULL' );
    }

    return md5_hex( join( '&', @ids ) );
}

sub _get_unique_cache_keys {
    my ( $self, $result ) = @_;
    my $mapper = $self->target_class->__mapper__;

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
        push @keys,  md5_hex( $name . '#' . join( '&', @uniq_ids ) );
    }

    return @keys;
}

sub _set_cache {
    my ( $self, $result ) = @_;
    my $cached_result = clone($result);
    $self->{cache}{ $self->_get_primary_cache_key($result) } = $cached_result;
    $self->{cache}{$_} = $cached_result
        for $self->_get_unique_cache_keys($result);
}

sub _clear_cache {
    my ( $self, $result ) = @_;
    delete $self->{cache}{ $self->_get_primary_cache_key($result) };
    delete $self->{cache}{ $_ } for $self->_get_unique_cache_keys($result);
}

1;
