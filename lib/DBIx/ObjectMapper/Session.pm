package DBIx::ObjectMapper::Session;
use strict;
use warnings;
use Carp::Clan qw/^DBIx::ObjectMapper/;
use Params::Validate qw(validate OBJECT BOOLEAN SCALAR);
use DBIx::ObjectMapper::Utils;
use DBIx::ObjectMapper::Session::Cache;
use DBIx::ObjectMapper::Session::Search;
use DBIx::ObjectMapper::Session::UnitOfWork;
use DBIx::ObjectMapper::Session::ObjectChangeChecker;
my $DEFAULT_SEARCH_CLASS = 'DBIx::ObjectMapper::Session::Search';

sub new {
    my $class = shift;

    my %attr = validate(
        @_,
        {   engine => { type => OBJECT, isa => 'DBIx::ObjectMapper::Engine' },
            autocommit   => { type => BOOLEAN, default => 1 },
            autoflush    => { type => BOOLEAN, default => 0 },
            share_object => { type => BOOLEAN, default => 0 },
            no_cache     => { type => BOOLEAN, default => 0 },
            cache        => {
                type      => OBJECT,
                callbacks => {
                    'ducktype' => sub {
                        ( grep { $_[0]->can($_) } qw(get set remove clear) )
                            == 4;
                        }
                },
                default => DBIx::ObjectMapper::Session::Cache->new()
            },
            search_class =>
                { type => SCALAR, default => $DEFAULT_SEARCH_CLASS },
            change_checker => {
                type => OBJECT,
                default =>
                    DBIx::ObjectMapper::Session::ObjectChangeChecker->new(),
                },
        }
    );

    $attr{transaction}
        = $attr{autocommit} ? undef : $attr{engine}->transaction;
    $attr{unit_of_work}
        = DBIx::ObjectMapper::Session::UnitOfWork->new(
        ( $attr{no_cache} ? undef : $attr{cache} ),
        $attr{search_class},
        $attr{change_checker},
        {   share_object => $attr{share_object},
            autoflush    => $attr{autoflush},
        },
    );

    return bless \%attr, $class;
}

sub autocommit  { $_[0]->{autocommit} }
sub uow         { $_[0]->{unit_of_work} }
sub engine      { $_[0]->{engine} }
sub autoflush   { $_[0]->{autoflush} }

sub search {
    my $self = shift;
    $self->flush;
    return $self->uow->search(@_);
}


sub get {
    my $self = shift;
    $self->flush;
    $self->uow->get(@_);
}

sub add {
    my $self = shift;
    my $obj  = shift || return;
    $self->uow->add($obj);
    $self->flush() if $self->autoflush;
    return $obj;
}

sub add_all {
    my $self = shift;
    $self->add($_) for @_;
    return @_;
}

sub flush {
    my $self = shift;
    $self->uow->flush();
}

sub delete {
    my $self = shift;
    my $obj  = shift;
    $self->uow->delete($obj);
    $self->flush() if $self->autoflush;
    return $obj;
}

sub transaction {
    my $self = shift;
    return $self->{transaction}
        if $self->{transaction} and !$self->{transaction}->complete;
    return $self->{transaction} = $self->engine->transaction;
}

sub commit {
    my $self = shift;
    $self->flush;
    unless( $self->autocommit ) {
        $self->transaction->commit;
        $self->transaction;
    }
}

sub rollback {
    my $self = shift;

    if( $self->autocommit ) {
        cluck "Can't rollback. autocommit is TRUE this session.";
        return;
    }

    $self->flush;
    $self->transaction->rollback;
}

sub txn {
    my $self = shift;
    my $code = shift;
    confess "it must be CODE reference" unless $code and ref $code eq 'CODE';
    $self->flush;
    return $self->{engine}->transaction(
        sub {
            local $self->{autoflush} = 1;
            local $self->uow->{option}{autoflush} = 1;
            $code->();
        },
    );
}

sub detach {
    my $self = shift;
    my $obj  = shift;
    $self->uow->detach($obj);
}

sub DESTROY {
    my $self = shift;
    local $@;
    eval {
        $self->rollback unless $self->autocommit;
        $self->uow->demolish;
    };
    warn $@ if $@; ## can't die in DESTROY...

    $self->{unit_of_work} = undef;
    warn "DESTROY $self" if $ENV{MAPPER_DEBUG};
    return;
}

1;

__END__

=head1 NAME

DBIx::ObjectMapper::Session

=head1 AUTHOR

Eisuke Oishi

=head1 COPYRIGHT

Copyright 2009 Eisuke Oishi

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
