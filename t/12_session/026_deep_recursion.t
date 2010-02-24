use strict;
use warnings;
use Test::More;

use DBIx::ObjectMapper;
use DBIx::ObjectMapper::Engine::DBI;

my $mapper = DBIx::ObjectMapper->new(
    engine => DBIx::ObjectMapper::Engine::DBI->new({
        dsn => 'DBI:SQLite:',
        username => '',
        password => '',
        on_connect_do => [
            q{CREATE TABLE customer( id integer primary key, name text, email text, email_type text )},
        ],
    }),
);

$mapper->metadata->t('customer' => 'autoload');

{
    package MyTest026::Customer;
    use strict;
    use warnings;

    sub new {
        my $class = shift;
        my $self = bless +{}, $class;

        my %attr = @_;
        for my $a ( keys %attr ) {
            $self->$a($attr{$a});
        }
        return $self;
    }

    sub id {
        my $self = shift;
        $self->{email} = shift if @_;
        return $self->{email};

    }

    sub name {
        my $self = shift;
        $self->{name} = shift if @_;
        return $self->{name};
    }

    sub email {
        my $self = shift;
        $self->{email} = shift if @_;
        $self->email_type($self->_def_email_type($self->{email}));
        return $self->{email};
    }

    sub _def_email_type {
        my ( $self, $email ) = @_;
        if( $email and $email eq 'foo@example.com' ) {
            return 'example';
        }
        else {
            return 'others';
        }
    }

    sub email_type {
        my $self = shift;
        $self->{email_type} = shift if @_;
        return $self->{email_type};
    }

    1;
};

$mapper->maps( $mapper->metadata->t('customer') => 'MyTest026::Customer' );

{
    my $session = $mapper->begin_session;
    ok my $cust = MyTest026::Customer->new(
        name => 'hoge',
        email => 'foo@example.com',
    );
};
done_testing;
