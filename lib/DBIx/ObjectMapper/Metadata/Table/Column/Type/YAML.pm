package DBIx::ObjectMapper::Metadata::Table::Column::Type::YAML;
use strict;
use warnings;
use base qw(DBIx::ObjectMapper::Metadata::Table::Column::Type::Text);
use YAML();

sub from_storage {
    my ( $self, $val ) = @_;
    return $val unless defined $val;
    return YAML::Load($val);
}

sub to_storage {
    my ( $self, $val ) = @_;
    return $val unless defined $val and ref($val);
    $val = $$val if ref $val eq 'REF';
    return YAML::Dump($val);
}

1;
