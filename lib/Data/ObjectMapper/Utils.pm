package Data::ObjectMapper::Utils;
use strict;
use warnings;
use Class::Inspector;
use Module::Pluggable::Object;
use Carp::Clan;
use Scalar::Util;
use Hash::Merge;

sub load_class {
    my $class_name = shift;
    return $class_name if loaded($class_name);

    if( my $error = load_not_ok($class_name) ) {
        exception($error);
    }

    exception(
        "require $class_name was successful but the package is not defined")
      unless loaded($class_name);

    return $class_name;
}

sub loaded { Class::Inspector->loaded($_[0]) }

sub load_not_ok {
    my $class_name = shift;

    my $error;
    {
        local $@;
        eval "require $class_name;";
        $error = $@;
    }

    return $error if $error;
    return;
}

sub load_classes_from_namespace {
    my $namespace = shift;

    my $loader = Module::Pluggable::Object->new(
        search_path => $namespace,
        require     => 0,
    );

    return $loader->plugins;
}

sub normalized_hash_to_array {
    my ($data) = @_;

    exception('Data Structure Error')
      unless ref $data eq 'ARRAY' and ref $data->[0] eq 'HASH';

    my @headers = sort keys %{$data->[0]};
    my @normalized;
    for my $d ( @$data ) {
        my @rray;
        for my $h ( @headers ) {
            push @rray, $d->{$h};
        }
        push @normalized, \@rray;
    }
    return \@headers, \@normalized;
}

sub normalized_array_to_hash {
    my ($data) = @_;

    exception('Data Structure Error')
      unless ref $data eq 'ARRAY' and ref $data->[0] eq 'ARRAY';

    my @headers = @{shift(@$data)};
    my @normalized;
    for my $d ( @$data ) {
        my %result;
        for my $i ( 0 .. $#headers ) {
            $result{$headers[$i]} = $d->[$i];
        }
        push @normalized, \%result;
    }

    return \@normalized;
}

sub is_deeply {
    my ( $X, $Y ) = @_;

    return 0 if !defined($X) and defined($Y);
    return 0 if defined($X) and !defined($Y);
    return 1 unless defined($X) and defined($Y);

    if( !ref($X) and !ref($Y) ) {
        if (    Scalar::Util::looks_like_number($X)
            and Scalar::Util::looks_like_number($Y) )
        {
            return $X == $Y ? 1 : ();
        }
        else {
            return $X eq $Y ? 1 : ();
        }
    }

    return unless ref($X) and ref($Y);
    return if ref($X) ne ref($Y);

    if( ref $X eq 'HASH' ) {
        return unless scalar(keys(%$X)) == scalar(keys(%$Y));
        for my $k (keys %$X ) {
            return unless is_deeply($X->{$k}, $Y->{$k});
        }
        return 1;
    }
    elsif( ref $X eq 'ARRAY' ) {
        return unless @$X == @$Y;
        for my $i ( 0 .. $#$X ) {
            return unless is_deeply($X->[$i], $Y->[$i]);
        }
        return 1;
    }
    elsif( ref $X eq 'SCALAR' ) {
        return is_deeply($$X, $$Y);
    }
    elsif( ref $X eq 'DateTime' ) {
        return is_deeply( $X . '', $Y . '' ); # to string
    }
    elsif( ref($X) =~ /^URI::/ and $X->can('as_string') ) {
        return is_deeply( $X->as_string, $Y->as_string );
    }
    else {
        warn( ref($X) . " is not supported." );
        return;
    }
}

sub merge_hashref {
    my ( $old, $new ) = @_;
    croak "Invlid Parameter. usage: merge_hashref(HashRef,HashRef)"
        unless ref $old eq 'HASH' and ref $new eq 'HASH';
    Hash::Merge::set_behavior( 'RIGHT_PRECEDENT' );
    return Hash::Merge::merge($old,$new);
}

1;
