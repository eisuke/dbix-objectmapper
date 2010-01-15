package Data::ObjectMapper::Session::Array;
use strict;
use warnings;
use base qw(Tie::Array);

sub new {
    my ( $class, $uow, @val ) = @_;
    my $array;
    tie @$array, $class, $uow;
    push @$array, @val;
    return $array;
}

sub TIEARRAY {
    my $class = shift;
    my $uow = shift;
    bless { value => +[], uow => $uow }, $class;
}

sub _remove {
    my $self = shift;
    $self->{uow}->delete($_) for grep { defined $_ } @_;
    return @_;
}

sub _add {
    my $self = shift;
    $self->{uow}->add($_) for grep { defined $_ } @_;
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

1;
