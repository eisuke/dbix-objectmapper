package DBIx::ObjectMapper::Metadata::Sugar;
use strict;
use warnings;
use Sub::Exporter;
use Module::Pluggable::Object;

sub Col {
    my $name = shift;
    my %args = @_;
    return {
        name => $name,
        %args,
    };
}

sub PrimaryKey() {
    return (
        primary_key => 1,
        is_nullable => 0,
    );
}

sub NotNull()      { is_nullable    => 0 }
sub Readonly()     { readonly       => 1 }
sub Unique()       { unique         => 1 }
sub OnUpdate(&)    { on_update      => $_[0] }
sub Default(&)     { default        => $_[0] }
sub Validation(&)  { validation     => $_[0] }
sub ToStorage(&)   { to_storage     => $_[0] }
sub FromStorage(&) { from_storage   => $_[0] }
sub ServerDefault  { server_default => $_[0] }
sub ForeignKey     { foreign_key    => [ $_[0] => $_[1] ] }
sub ServerCheck    { server_check   => $_[0] }

my @types;
{
    my $namespace = 'DBIx::ObjectMapper::Metadata::Table::Column::Type';
    my $loader = Module::Pluggable::Object->new(
        search_path => [ $namespace ],
        require     => 1,
    );

    my $pkg = __PACKAGE__;
    for my $type_class ( $loader->plugins ) {
        my $name = $type_class;
        $name =~ s/^$namespace\:://;
        no strict 'refs';
        *{"$pkg\::$name"} = sub { type => $type_class->new(@_) };
        push @types, $name;
    }
};

my @FUNC = (
    qw(Col PrimaryKey NotNull OnUpdate Default ToStorage Unique
       FromStorage ServerDefault Readonly ForeignKey ServerCheck
       Validation),
    @types,
);

Sub::Exporter::setup_exporter({
    exports => [ @FUNC ],
    groups  => {
        all => [ @FUNC ],
    }
});

1;
