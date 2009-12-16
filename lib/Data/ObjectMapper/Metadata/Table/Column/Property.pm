package Data::ObjectMapper::Metadata::Table::Column::Property;
use strict;
use warnings;

use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw(type size is_nullable default custom is_utf8 is_readonly));

sub new {
    my ($class, %property) = @_;
    bless { %property }, $class;
}

sub inflate {
    my ( $self, $val ) = @_;

    return $val;
}

sub deflate {
    my ( $self, $val ) = @_;
    return $val;
}

1;
