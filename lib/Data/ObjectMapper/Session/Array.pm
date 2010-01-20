package Data::ObjectMapper::Session::Array;
use strict;
use warnings;
use Scalar::Util qw(refaddr weaken);
use base qw(Tie::Array);

sub new {
    my ( $class, $mapper, @val ) = @_;
    my $array;
    tie @$array, $class, $mapper;
    push @$array, @val;
    return $array;
}

sub TIEARRAY {
    my $class = shift;
    my $mapper = shift;
    my $uow = $mapper->unit_of_work;

    my $self = bless {
        value      => +[],
        uowaddr    => refaddr($uow),
        uow        => ref($uow),
        mapperaddr => refaddr($mapper),
        mapper     => ref($mapper),
    }, $class;
    return $self;
}

sub uow {
    my $self = shift;
    return $self->{uow}->instance( $self->{uowaddr} );
}

sub mapper {
    my $self = shift;
    return $self->{mapper}->get( $self->{mapperaddr} );
}

sub _remove {
    my $self = shift;
    if ( my $uow = $self->uow ) {
        $uow->delete($_) for grep { defined $_ } @_;
    }
    return @_;
}

sub _add {
    my $self = shift;
    if ( my $uow = $self->uow ) {
        $uow->add($_) for grep { defined $_ } @_;
    }
    return @_;
}

sub FETCHSIZE { scalar @{$_[0]->{value}} }

sub FETCH {
    my ($self, $index) = @_;
    return $self->{value}->[$index];
}

sub STORESIZE {}

sub STORE {
    my ( $self, $index, $value ) = @_;
    $self->{value}->[$index] = $value;
    $self->_add($value);
    return $self->FETCHSIZE;
}

sub SHIFT {
    my $self = shift;
    my $val = shift(@{$self->{value}});
    $self->_remove($val);
    return $val;
}

sub POP {
    my $self = shift;
    my $val = pop(@{$self->{value}});
    $self->_remove($val);
    return $val;
}

sub SPLICE {
    my $self = shift;
    my $sz  = $self->FETCHSIZE;
    my $off = @_ ? shift : 0;
    $off   += $sz if $off < 0;
    my $len = @_ ? shift : $sz-$off;
    my @add = @_;
    my @remove = splice( @{ $self->{value} }, $off, $len, @add );
    $self->_add(@add) if @add;
    $self->_remove(@remove) if @remove;
    return @remove;
}

sub CLEAR {
    my $self = shift;
    $self->_remove(@{$self->{value}});
    $self->{value} = [];
    return;
}

sub DESTROY {
    my $self = shift;
    warn "DESTROY $self" if $ENV{MAPPER_DEBUG};
}

1;
