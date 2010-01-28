package Data::ObjectMapper::Metadata::Table::Column::Type::YAML;
use strict;
use warnings;
use base qw(Data::ObjectMapper::Metadata::Table::Column::Type::Text);
use YAML();

sub from_storage {
    my ( $self, $val ) = @_;
    return $val unless defined $val;
    return YAML::Load($val);
}

sub to_storage {
    my ( $self, $val ) = @_;
    return $val unless defined $val and ref($val);
    return YAML::Dump($val);
}

1;
