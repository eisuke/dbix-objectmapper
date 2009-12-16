package Data::ObjectMapper::Log;
use strict;
use warnings;
use Carp::Clan;
use List::MoreUtils qw(any);

our @LEVELS = qw( TRACE DEBUG INFO DRIVER_TRACE WARN ERROR FATAL );
our %LEVEL_TABLE = ();

{
    no strict 'refs';
    for ( my $i = 0 ; $i <= $#LEVELS ; $i++ ) {
        my $name = lc($LEVELS[$i]);
        my $level = $i;
        $LEVEL_TABLE{$name} = $level;

        *{$name} = sub {
            my $self = shift;
            return $self->level <= $level ? $self->_log(uc($name), @_) : undef;
        };

        *{"is_$name"} = sub {
            my $self = shift;
            return  $self->level <= $level;
        };
    }
};

sub _log {
    my $self = shift;
    my $error_msg = $self->render_msg(@_);
    my $level = shift;
    if( $LEVEL_TABLE{lc($level)} > 3 ) {
        warn $error_msg;
    }
    else {
        print STDERR $error_msg;
    }
    return $error_msg;
}

sub render_msg {
    my $self = shift;
    my $level = shift;
    my $msg = join "\n", @_;
    $msg .= "\n" unless $msg =~ /\n$/;
    return sprintf("[%s] %s", $level, $msg);
}

sub level { $_[0]->{level} }

sub new {
    my $class = shift;
    my $level =
         $class->get_level( $_[0] )
      || $class->get_level_from_env
      || $LEVEL_TABLE{warn};

    bless{
        level => $level,
    }, $class;
}

sub set_level {
    my $self = shift;
    $self->{level} = $self->get_level(shift);
}

sub get_level {
    my $class = shift;
    my $level = shift;
    if ( $level and !ref $level and any { uc($level) eq $_ } @LEVELS ) {
        return $LEVEL_TABLE{lc($level)};
    }
}

sub get_level_from_env {
    my $class = shift;
    if ( my @trace_env = grep( /^DBSTORM_[A-Z_]+$/, keys %ENV ) ) {
        for my $lev (@LEVELS) {
            return $LEVEL_TABLE{lc($lev)} if $ENV{ 'DBSTORM_' . uc($lev) };
        }
    }
}

sub dump {
    my $self = shift;
    require Data::Dumper;
    $self->debug( Data::Dumper::Dumper(\@_) );
}

sub exception {
    my ( $self, $msg ) = @_;
    my $error_msg;
    {
        local $@;
        eval{ confess $msg };
        $error_msg = $@;
    };

    die $self->render_msg('FATAL', $error_msg);
}

1;
