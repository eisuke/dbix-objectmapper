package DBIx::ObjectMapper::Engine::DBI::Driver::Oracle;
use strict;
use warnings;
use Try::Tiny;
use Carp::Clan qw/^DBIx::ObjectMapper/;
use base qw(DBIx::ObjectMapper::Engine::DBI::Driver);
use DBIx::ObjectMapper::Engine::DBI::BoundParam;
use DBD::Oracle qw(:ora_types);
use Scalar::Util qw(blessed);

sub init {
    my $self = shift;
    my $dbh  = shift;

    try {
        require DateTime::Format::Oracle;
        DateTime::Format::Oracle->import;
        $self->{datetime_parser} ||= 'DateTime::Format::Oracle';
    } catch {
        confess "Couldn't load DateTime::Format::Oracle: $_";
    };

    $self->{db_schema} ||= do {
        my $system_context_row_ref = $dbh->selectall_arrayref("select sys_context( 'userenv', 'current_schema' ) from dual");
        $system_context_row_ref->[0][0];
    };

    $self->{_cache}->{_oracle} = {
        primary_keys => {},
        foreign_keys => {},
        unique_info  => {},
    };
    $self->{namesep} = q{.};
    $self->{quote}   = q{'};
}

sub last_insert_id {}

sub get_primary_key {
    my ($self, $dbh, $table) = @_;
    if (!$self->{_cache}->{_oracle}->{primary_keys}->{$table}) {
         $self->{_cache}->{_oracle}->{primary_keys}->{$table} =
            #+[keys %{$dbh->primary_key_info('', $self->db_schema, $table)->fetchall_hashref('COLUMN_NAME')}];
            +[keys %{$self->_primary_key_info($dbh, '', $self->db_schema, $table)->fetchall_hashref('COLUMN_NAME')}];
    }
    return @{$self->{_cache}->{_oracle}->{primary_keys}->{$table}};
}

sub get_table_uniq_info {
    my ($self, $dbh, $table) = @_;
    if (!$self->{_cache}->{_oracle}->{unique_info}->{$table}) {
        my $sth = $dbh->prepare(q{
            select ai.index_name, aic.column_name
            from all_indexes ai
            join all_ind_columns aic
            on aic.index_name = ai.index_name
            and aic.index_owner = ai.owner
            where ai.uniqueness = 'UNIQUE'
            and aic.table_name = ?
            and aic.index_owner = ?
        });
        $sth->execute($table, $self->db_schema);

        my $unique_rows = $sth->fetchall_arrayref();
        my %unique_constraints = map {
            $_->[0] => []
        } @$unique_rows;
        for my $row (@$unique_rows) {
            push @{$unique_constraints{$row->[0]}}, $row->[1];
        }

        $self->{_cache}->{_oracle}->{unique_info}->{$table} = [
            map {
                [$_ => $unique_constraints{$_}]
            } keys %unique_constraints
        ];
    }

    return $self->{_cache}->{_oracle}->{unique_info}->{$table};
}

sub get_table_fk_info {
    my ($self, $dbh, $table) = @_;

    if (!$self->{_cache}->{_oracle}->{foreign_keys}->{$table}) {
        #my $sth = $dbh->foreign_key_info(undef, undef, undef, '', $self->db_schema, $table);
        my $sth = $self->_foreign_key_info($dbh,undef, undef, undef, '', $self->db_schema, $table);
        my %constraints = ();

        while (my $row = $sth->fetchrow_hashref) {
            my $constraint_name = $row->{FK_NAME};
            if (!$constraints{$constraint_name}) {
                $constraints{$constraint_name} = {
                    keys  => [],
                    refs  => [],
                    table => $row->{UK_TABLE_NAME},
                };
            }

            my $constraint_info = $constraints{$constraint_name};
            push @{$constraint_info->{keys}}, $row->{FK_COLUMN_NAME};
            push @{$constraint_info->{refs}}, $row->{UK_COLUMN_NAME};
        }

        $self->{_cache}->{_oracle}->{foreign_keys}->{$table} = [values %constraints];
    }

    return $self->{_cache}->{_oracle}->{foreign_keys}->{$table};
}

sub get_tables {
    my ( $self, $dbh ) = @_;
    return $self->_truncate_quote_and_sep(
        sort {$a cmp $b}
        grep { $_ !~ /\.BIN\$/ }
        map {$_ =~ s/"//g; $_}
        (
            $dbh->tables(undef, $self->db_schema, undef, 'TABLE'),
            $dbh->tables(undef, $self->db_schema, undef, 'VIEW')
        )
    );
}

sub set_time_zone_query {
    my ( $self, $dbh ) = @_;
    my $tz = $self->time_zone || return;
    return "ALTER SESSION SET time_zone = " . $dbh->quote($tz);
}

sub set_savepoint {
    my ($self, $dbh, $name) = @_;
    my $quoted_name = $dbh->quote($name);
    $dbh->do("SAVEPOINT $quoted_name");
}

sub release_savepoint {}

sub rollback_savepoint {
    my ($self, $dbh, $name) = @_;
    my $quoted_name = $dbh->quote($name);
    $dbh->do("ROLLBACK TO $quoted_name");
}

sub bind_params {
    my ($self, $sth, @binds) = @_;
    my $bind_position = 0;

    return map {
        my $bind = $_;
        $bind_position++;

        if (ref $bind && blessed($bind) && $bind->isa('DBIx::ObjectMapper::Engine::DBI::BoundParam')) {
            if ($bind->type eq 'binary') {
                $sth->bind_param(
                    $bind_position,
                    undef,
                    {
                        ora_type  => SQLT_BIN,
                        ora_field => $bind->column
                    }
                );
            }
            else {
                confess 'Unknown type for a bound param: ' . $bind->type;
            }
            $bind->value;
        }
        else {
            $bind;
        }
    } @binds;
}

sub _type_map_data {
    my $class = shift;
    my $map = $class->SUPER::_type_map_data(@_);
    $map->{number}   = 'Numeric';
    $map->{blob}     = 'Blob';
    $map->{long}     = 'Binary';
    $map->{varchar2} = 'Text';
    return $map;
}

sub type_map {
    my $class = shift;
    my $type  = shift;
    $type =~ s/\(.*$//;
    return $class->_type_map_data->{$type};
}

###### horrid DBD::Oracle override below 
###### REMOVE WHEN PERL IS UPGRADED!!!!!
###### code base from DBD::Oracle v1.68

sub _primary_key_info {
    my($self, $dbh, $catalog, $schema, $table) = @_;
    if (ref $catalog eq 'HASH') {
        ($schema, $table) = @$catalog{'TABLE_SCHEM','TABLE_NAME'};
        $catalog = undef;
    }
    my $SQL = <<'SQL';
SELECT *
  FROM
(
  SELECT /*+ CHOOSE */
         NULL              TABLE_CAT
       , c.OWNER           TABLE_SCHEM
       , c.TABLE_NAME      TABLE_NAME
       , c.COLUMN_NAME     COLUMN_NAME
       , c.POSITION        KEY_SEQ
       , c.CONSTRAINT_NAME PK_NAME
    FROM ALL_CONSTRAINTS   p
       , ALL_CONS_COLUMNS  c
   WHERE p.OWNER           = c.OWNER
     AND p.TABLE_NAME      = c.TABLE_NAME
     AND p.CONSTRAINT_NAME = c.CONSTRAINT_NAME
     AND p.CONSTRAINT_TYPE = 'P'
)
 WHERE TABLE_SCHEM = ?
   AND TABLE_NAME  = ?
 ORDER BY TABLE_SCHEM, TABLE_NAME, KEY_SEQ
SQL
#warn "@_\n$Sql ($schema, $table)";
    my $sth = $dbh->prepare($SQL) or return undef;
    $sth->execute($schema, $table) or return undef;
    $sth;
}

sub _foreign_key_info {
    my $self = shift;
    my $dbh  = shift;
    my $attr = ( ref $_[0] eq 'HASH') ? $_[0] : {
        'UK_TABLE_SCHEM' => $_[1],'UK_TABLE_NAME ' => $_[2]
            ,'FK_TABLE_SCHEM' => $_[4],'FK_TABLE_NAME ' => $_[5] };
    my $SQL = <<'SQL';  # XXX: DEFERABILITY
SELECT *
  FROM
(
  SELECT /*+ CHOOSE */
         to_char( NULL )    UK_TABLE_CAT
       , uk.OWNER           UK_TABLE_SCHEM
       , uk.TABLE_NAME      UK_TABLE_NAME
       , uc.COLUMN_NAME     UK_COLUMN_NAME
       , to_char( NULL )    FK_TABLE_CAT
       , fk.OWNER           FK_TABLE_SCHEM
       , fk.TABLE_NAME      FK_TABLE_NAME
       , fc.COLUMN_NAME     FK_COLUMN_NAME
       , uc.POSITION        ORDINAL_POSITION
       , 3                  UPDATE_RULE
       , decode( fk.DELETE_RULE, 'CASCADE', 0, 'RESTRICT', 1, 'SET NULL', 2, 'NO ACTION', 3, 'SET DEFAULT', 4 )
                            DELETE_RULE
       , fk.CONSTRAINT_NAME FK_NAME
       , uk.CONSTRAINT_NAME UK_NAME
       , to_char( NULL )    DEFERABILITY
       , decode( uk.CONSTRAINT_TYPE, 'P', 'PRIMARY', 'U', 'UNIQUE')
                            UNIQUE_OR_PRIMARY
    FROM ALL_CONSTRAINTS    uk
       , ALL_CONS_COLUMNS   uc
       , ALL_CONSTRAINTS    fk
       , ALL_CONS_COLUMNS   fc
   WHERE uk.OWNER            = uc.OWNER
     AND uk.CONSTRAINT_NAME  = uc.CONSTRAINT_NAME
     AND fk.OWNER            = fc.OWNER
     AND fk.CONSTRAINT_NAME  = fc.CONSTRAINT_NAME
     AND uk.CONSTRAINT_TYPE IN ('P','U')
     AND fk.CONSTRAINT_TYPE  = 'R'
     AND uk.CONSTRAINT_NAME  = fk.R_CONSTRAINT_NAME
     AND uk.OWNER            = fk.R_OWNER
     AND uc.POSITION         = fc.POSITION
)
 WHERE 1              = 1
SQL
    my @BindVals = ();
    while ( my ( $k, $v ) = each %$attr ) {
        if ( $v ) {
            $SQL .= "   AND $k = ?\n";
            push @BindVals, $v;
        }
    }
    $SQL .= " ORDER BY UK_TABLE_SCHEM, UK_TABLE_NAME, FK_TABLE_SCHEM, FK_TABLE_NAME, ORDINAL_POSITION\n";
    my $sth = $dbh->prepare( $SQL ) or return undef;
    $sth->execute( @BindVals ) or return undef;
    $sth;
}

1;
