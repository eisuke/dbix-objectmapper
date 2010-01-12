package Data::ObjectMapper::Metadata::Table::Column;
use strict;
use warnings;
use Carp::Clan;
use base qw(Class::Accessor::Fast Clone);

use Encode;
use Scalar::Util();
use Params::Validate qw(:all);

use overload
    '==' => \&eq,
    '!=' => sub { $_[0]->op( '!=', $_[1] ) },
    '<=' => sub { $_[0]->op( '<=', $_[1] ) },
    '>=' => sub { $_[0]->op( '>=', $_[1] ) },
    '>'  => sub { $_[0]->op( '>',  $_[1] ) },
    '<'  => sub { $_[0]->op( '<',  $_[1] ) },
    ### XXXX to connect object
    '+'  => sub { $_[0] . ' || ' . $_[1] },
    '""' => sub { $_[0]->table . $_[0]->sep . $_[0]->name },
    fallback => 1,
;

my $ATTRIBUTES = {
    name  => { type => SCALAR },
    table => { type => SCALAR },
    sep   => { type => SCALAR },
    type  => { type => SCALAR },
    size  => {
        type     => SCALAR | UNDEF,
        callback => sub { defined $_[0] ? $_[0] =~ /^\d+$/ : 1 }
    },
    is_nullable => { type => BOOLEAN },
    default     => { type => SCALAR | UNDEF | CODEREF | ARRAYREF },
    on_update   => { type => SCALAR | UNDEF | CODEREF | ARRAYREF },
    utf8        => { type => BOOLEAN | UNDEF },
    readonly    => { type => BOOLEAN | UNDEF },
    inflate     => { type => CODEREF | UNDEF },
    deflate     => { type => CODEREF | UNDEF },
    validation  => { type => CODEREF | UNDEF },
};


__PACKAGE__->mk_ro_accessors( map{ $_ } keys %$ATTRIBUTES );

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
        return \@_;
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
    $self . ' DESC';
}

sub as { [ $_[0], $_[1] ] }

sub is { $_[0]->name => $_[1] || undef }

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
            if( ref $update eq 'CODE' ) {
                $val = $update->($val);
            }
            else {
                $val = $update;
            }
        }
    }
    else {
        if( !defined $val and my $default = $self->default ) {
            if( ref $default eq 'CODE' ) {
                $val = $default->();
            }
            else {
                #$val = $default; XXXX
            }
        }
    }

    if( defined $val and my $deflate = $self->deflate ) {
        $val = $deflate->($val);
    }


    if( defined $val and $self->utf8 and Encode::is_utf8($val) ) {
        $val = Encode::encode( 'utf8', $val )
    }

    return $val;
}

sub to_storage_on_update {
    my ( $self, $val ) = @_;
    return $self->to_storage($val, 1);
}

sub from_storage {
    my ( $self, $val ) = @_;

    $val = $self->inflate->($val) if $val and $self->inflate;
    $val = Encode::decode( 'utf8', $val )
        if $val and $self->utf8 and !Encode::is_utf8($val);

    return $val;
}

1;
