package Data::ObjectMapper::Metadata::Table::Column::Base;
use strict;
use warnings;
use Carp::Clan;
use base qw(Clone);
use Encode;
use Scalar::Util;
use Params::Validate qw(:all);
use Data::ObjectMapper::Utils;
use Data::ObjectMapper::Metadata::Table::Column::Desc;
use Data::ObjectMapper::Metadata::Table::Column::Connect;

use overload
    '==' => \&eq,
    '!=' => sub { $_[0]->op( '!=', $_[1] ) },
    '<=' => sub { $_[0]->op( '<=', $_[1] ) },
    '>=' => sub { $_[0]->op( '>=', $_[1] ) },
    '>'  => sub { $_[0]->op( '>',  $_[1] ) },
    '<'  => sub { $_[0]->op( '<',  $_[1] ) },
    '+'  => \&conc,
    '""' => sub{ $_[0]->as_string },
    fallback => 1,
;

sub as_string { $_[0]->table . $_[0]->sep . $_[0]->name }

sub connc   {
    Data::ObjectMapper::Metadata::Table::Column::Connect->new(
        $_[0], $_[1]
    );
}

my $ATTRIBUTES = {
    name  => { type => SCALAR },
    table => { type => SCALAR },
    sep   => { type => SCALAR },
    type  => {
        type => OBJECT,
        isa  => 'Data::ObjectMapper::Metadata::Table::Column::Type'
    },
    is_nullable    => { type => BOOLEAN },
    default        => { type => CODEREF|UNDEF, optional => 1 },
    server_default => { type => SCALAR|UNDEF, optional => 1 },
    server_check   => { type => SCALAR|UNDEF, optional => 1 },
    on_update      => { type => CODEREF|UNDEF, optional => 1 },
    readonly       => { type => BOOLEAN|UNDEF, optional => 1 },
    from_storage   => { type => CODEREF|UNDEF, optional => 1 },
    to_storage     => { type => CODEREF|UNDEF, optional => 1 },
    validation     => { type => CODEREF|UNDEF, optional => 1 },
    # AutoIncrement XXXXX
};

sub name           { $_[0]->{name} }
sub table          { $_[0]->{table} }
sub sep            { $_[0]->{sep} }
sub type           { $_[0]->{type} }
sub is_nullable    { $_[0]->{is_nullable} }
sub default        { $_[0]->{default} }
sub server_default { $_[0]->{server_default} }
sub server_check   { $_[0]->{server_check} }
sub on_update      { $_[0]->{on_update} }
sub readonly       { $_[0]->{readonly} }
sub validation     { $_[0]->{validation} }

sub new {
    my $class = shift;
    my %attr = validate( @_, $ATTRIBUTES );
    return bless \%attr, $class;
}

sub op {
    my ( $self, $op, $val ) = @_;

    if( Scalar::Util::blessed($val) and ref $val eq ref $self ) {
        my $col = $val . "";
        return [ $self, $op, \$col ];
    }
    else {
        if( (ref $val || '') eq 'ARRAY' ) {
            $val = [ map { $self->type->to_storage($_) } @$val ];
        }
        elsif( $val and !ref($val) ) {
            $val = $self->type->to_storage($val);
        }
        return [ $self, $op, $val ];
    }
}

sub eq { $_[0]->op( '=', $_[1] ) }

sub between {
    my ($self, $from, $to) = @_;
    $self->op( 'BETWEEN', [ $from, $to ] );
}

sub in {
    my ($self, @values) = @_;
    $self->op( 'IN', \@values );
}

sub not_in {
    my ($self, @values) = @_;
    $self->op( 'NOT IN', \@values );
}

sub like { $_[0]->op( 'LIKE', $_[1]) }

sub not_like { $_[0]->op( 'NOT LIKE', $_[1]) }

sub desc {
    my $self = shift;
    return Data::ObjectMapper::Metadata::Table::Column::Desc->new($self);
}

sub as { [ $_[0], $_[1] ] }

sub is { $_[0]->name => $_[1] || undef }

sub as_alias {
    my $self = shift;
    my $name = shift;
    my $clone = $self->clone;
    $clone->{table} = $name;
    return $clone;
}

sub to_storage {
    my ( $self, $val, $on_update ) = @_;

    if( $on_update and $self->readonly ) {
        confess $self . " is READONLY column.";
    }

    if( defined $val and my $validation = $self->validation ) {
        unless( $validation->($val) ) {
            confess $self . " : Validation Error.";
        }
    }

    if( $on_update ) {
        if( my $update = $self->on_update ) {
            $val = $update->($val);
        }
    }
    else {
        if( !defined $val ) {
            if( my $default = $self->default ) {
                $val = $default->();
            }
            elsif( my $server_default = $self->server_default ) {
                $val = \$server_default;
            }
        }
    }

    if( defined $val and my $to_storage = $self->{to_storage} ) {
        $val = $to_storage->($val);
    }

    return $self->type->to_storage($val);
}

sub to_storage_on_update {
    my ( $self, $val ) = @_;
    return $self->to_storage($val, 1);
}

sub from_storage {
    my ( $self, $val ) = @_;
    $val = $self->{from_storage}->($val) if $val and $self->{from_storage};
    return $self->type->from_storage($val);
}

sub DESTROY {
    my $self = shift;
    warn "DESTROY $self" if $ENV{MAPPER_DEBUG};
}

1;
