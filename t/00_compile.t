use Test::More;
use Module::Pluggable::Object;

BEGIN{
    my $loader = Module::Pluggable::Object->new(
        search_path => [ 'Data::ObjectMapper' ],
        require     => 0,
    );

    my @classes = $loader->plugins;
    unshift @classes , 'Data::ObjectMapper';

    plan tests => scalar(@classes);
    require_ok($_) for sort @classes;
}
