use strict;
use warnings;
use Test::More;
use Class::MOP;

sub build_pkg($) {
    my $t = shift;
    my $pkg = 'Data::ObjectMapper::Metadata::Table::Column::Type::' . $t;
    Class::MOP::load_class($pkg);
    return $pkg;
}

{
    my $type = 'String';
    my $pkg = build_pkg $type;
    my $obj = $pkg->new( 10, 'utf8' );
    is $obj->type, lc($type);
    ok $obj->utf8;
    is $obj->size, 10;
};

{
    my $type = 'Text';
    my $pkg = build_pkg $type;
    my $obj = $pkg->new;
    is $obj->type, lc($type);

};

{
    my $type = 'Int';
    my $pkg = build_pkg $type;
    my $obj = $pkg->new;
    is $obj->type, lc($type);

};

{
    my $type = 'SmallInt';
    my $pkg = build_pkg $type;
    my $obj = $pkg->new;
    is $obj->type, lc($type);

};

{
    my $type = 'BigInt';
    my $pkg = build_pkg $type;
    my $obj = $pkg->new;
    is $obj->type, lc($type);

};

{
    my $type = 'Numeric';
    my $pkg = build_pkg $type;
    my $obj = $pkg->new;
    is $obj->type, lc($type);

};

{
    my $type = 'Float';
    my $pkg = build_pkg $type;
    my $obj = $pkg->new;
    is $obj->type, lc($type);

};

{
    my $type = 'DateTime';
    my $pkg = build_pkg $type;
    my $obj = $pkg->new;
    is $obj->type, lc($type);

};

{
    my $type = 'Date';
    my $pkg = build_pkg $type;
    my $obj = $pkg->new;
    is $obj->type, lc($type);

};

{
    my $type = 'Time';
    my $pkg = build_pkg $type;
    my $obj = $pkg->new;
    is $obj->type, lc($type);

};

{
    my $type = 'Interval';
    my $pkg = build_pkg $type;
    my $obj = $pkg->new;
    is $obj->type, lc($type);


};

{
    my $type = 'Boolean';
    my $pkg = build_pkg $type;
    my $obj = $pkg->new;
    is $obj->type, lc($type);


};

{
    my $type = 'Binary';
    my $pkg = build_pkg $type;
    my $obj = $pkg->new;
    is $obj->type, lc($type);

};

{
    my $type = 'Storable';
    my $pkg = build_pkg $type;
    my $obj = $pkg->new;
    is $obj->type, lc($type);


};

{
    my $type = 'Array';
    my $pkg = build_pkg $type;
    my $obj = $pkg->new;
    is $obj->type, lc($type);

};


done_testing;
