package Data::ObjectMapper::SQL::Insert;
use strict;
use warnings;
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
        if (    @_ == 2
            and ref $_[0] eq 'ARRAY'
            and ref $_[1] eq 'Data::ObjectMapper::SQL::Select' )
        {
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
    if (    @_ == 2
        and ref $_[0] eq 'ARRAY'
        and ref $_[1] eq 'Data::ObjectMapper::SQL::Select' )
    {
        $self->{values} = \@_;
    }
    elsif ( @_ % 2 == 0 ) {
        my %values = @_;
        $self->{values}{$_} = $values{$_} for keys %values;
    }
}

sub values_as_sql {
    my $self = shift;
    if ( ref $self->{values} eq 'HASH' ) {
        my ( @col, @val );

        for my $key ( sort keys %{ $self->{values} } ) {
            push @col, $key;
            push @val,
                $self->convert_val_to_sql_format( $self->{values}{$key} );
        }

        return sprintf(
            " ( %s ) VALUES(%s)",
            join( ', ', @col ),
            join( ',', ('?') x @val )
        ), @val;
    }
    elsif ( ref $self->{values} eq 'ARRAY' ) {
        my ( $stm, @bind ) = $self->{values}[1]->as_sql;

        return sprintf( " ( %s ) %s",
            join( ', ', @{ $self->{values}[0] } ), $stm ),
            @bind;
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

    my ($value_stm, @value_bind) = $self->values_as_sql;
    $stm .= $value_stm;
    push @bind, @value_bind if @value_bind;

    return ( $stm, @bind );
}

1;
