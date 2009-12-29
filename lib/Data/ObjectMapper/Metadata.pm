package Data::ObjectMapper::Metadata;
use strict;
use warnings;
use Data::ObjectMapper::Metadata::Table;

my $DEFAULT_QUERY_CLASS = 'Data::ObjectMapper::Query';

sub new {
    my $class = shift;
    my %attr = @_;

    bless {
        tables       => +{},
        engine       => $attr{engine} || undef,
        query_class  => $attr{query_class} || $DEFAULT_QUERY_CLASS,
        query_object => undef,
    }, $class;
}

sub engine {
    my $self = shift;
    if( @_ ) {
        my $engine = shift;
        $self->{engine} = $engine;
        $_->engine($engine) for values %{$self->table};
    }

    return $self->{engine};
}

sub table {
    my $self = shift;

    if ( @_  == 2 ) {
        my $table_name = shift;
        my $attr = shift;
        $attr->{engine} ||= $self->engine if $self->engine;
        $self->{tables}{$table_name}
            = Data::ObjectMapper::Metadata::Table->new( $table_name, $attr );
    }
    elsif( @_ == 1 ) {
        my $table_name = shift;
        return $self->{tables}{$table_name};
    }
    else {
        return $self->{tables};
    }
}

*t = \&table;

sub query_object {
    my $self = shift;
    return $self->{query_object} ||= $self->{query_class}->new($self->engine);
}

sub select { $_[0]->query_object->select }
sub insert { $_[0]->query_object->insert }
sub delete { $_[0]->query_object->delete }
sub update { $_[0]->query_object->update }

1;
