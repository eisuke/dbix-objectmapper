package Data::ObjectMapper::SQL::Insert;
use strict;
use warnings;
use Carp;
use base qw(Data::ObjectMapper::SQL::Base);

__PACKAGE__->initdata({
    table  => undef,
    values => {},
});

__PACKAGE__->accessors({
    convert_table_to_sql => [qw(table)],
});

sub values {
    my $self = shift;
    if( @_ ) {
        if ( ref $_[0] eq 'ARRAY' ) {
            $self->{values} = \@_;
        }
        elsif( @_ % 2 == 0 ) {
            $self->{values} = {@_};
        }
        elsif( @_ == 1 ) {
            $self->{values} = $_[0];
        }

        return $self;
    }

    return $self->{values};
}

sub add_values {
    my $self = shift;
    if ( ref $_[0] eq 'ARRAY' ) {
        $self->values(@_);
    }
    elsif ( @_ % 2 == 0 ) {
        my %values = @_;
        $self->{values}{$_} = $values{$_} for keys %values;
    }
}

sub _values_as_sql {
    my $self = shift;
    my $values = shift;

    if ( ref $values eq 'HASH' ) {
        my ( @col, @val );

        for my $key ( sort keys %$values ) {
            push @col, $key;
            push @val, $self->convert_val_to_sql_format( $values->{$key} );
        }

        return sprintf(
            " ( %s ) VALUES (%s)",
            join( ', ', @col ),
            join( ',', ('?') x @val )
        ), @val;
    }
    elsif ( ref $values eq 'ARRAY' ) {
        if ( ref $values->[1] eq 'ARRAY' ) {
            my $col = shift(@$values);
            my $stm = sprintf(" ( %s ) VALUES ", join( ', ', @$col) );
            my @multi_stm;
            my @bind_val;
            for my $v ( @$values ) {
                push @multi_stm, sprintf("(%s)", join(',', ('?') x @$v));
                push @bind_val, @$v;
            }
            $stm .= join(', ', @multi_stm );
            return $stm, @bind_val;
        }
        elsif( ref $values->[1] eq 'Data::ObjectMapper::SQL::Select' ) {
            my ( $stm, @bind ) = $values->[1]->as_sql;
            return sprintf( " ( %s ) %s",
                join( ', ', @{ $values->[0] } ), $stm ),
                @bind;
        }
    }
    else {
        return;
    }
}

sub as_sql {
    my $self = shift;
    my ($stm, @bind);

    my ( $table_name, @no_bind ) = $self->table_as_sql;
    $stm = 'INSERT INTO ' . $table_name;

    my ($value_stm, @value_bind) = $self->_values_as_sql($self->{values});
    $stm .= $value_stm;
    push @bind, @value_bind if @value_bind;

    return ( $stm, @bind );
}

1;
