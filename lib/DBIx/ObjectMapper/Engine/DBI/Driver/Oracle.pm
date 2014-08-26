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
        $self->{_cache}->{_oracle}->{foreign_keys}->{$table} = $self->_foreign_key_info($dbh,undef, undef, undef, '', $self->db_schema, $table);
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

###### DBD::Oracle override below because DBD::Oracle is inefficient for large schemas
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

sub build_constraint_cache {
    my ($self, $dbh, $attr) = @_;
    my $cache = {};
    my $sth;

    $sth = $dbh->prepare(q{
        select OWNER, R_OWNER, TABLE_NAME, CONSTRAINT_NAME, R_CONSTRAINT_NAME, CONSTRAINT_TYPE
          from ALL_CONSTRAINTS
          where CONSTRAINT_TYPE in ('P','U', 'R')
    }) or return undef;
    $sth->execute() or return undef;
    $cache->{constraints} = [map {
                                +{
                                    OWNER             => $_->[0],
                                    R_OWNER           => $_->[1],
                                    TABLE_NAME        => $_->[2],
                                    CONSTRAINT_NAME   => $_->[3],
                                    R_CONSTRAINT_NAME => $_->[4],
                                    CONSTRAINT_TYPE   => $_->[5],
                                }
                            }
                            @{$sth->fetchall_arrayref}];

    $sth = $dbh->prepare(q{
        select OWNER, CONSTRAINT_NAME, COLUMN_NAME, POSITION
          from ALL_CONS_COLUMNS
         order by POSITION
    }) or return undef;
    $sth->execute() or return undef;
    $cache->{columns} = [map {
                                +{
                                    OWNER           => $_->[0],
                                    CONSTRAINT_NAME => $_->[1],
                                    COLUMN_NAME     => $_->[2],
                                    POSITION        => $_->[3],
                                }
                            }
                        @{$sth->fetchall_arrayref}];

    $self->{_constraint_cache} = $cache;
    return 1;
}

sub _foreign_key_info {
    my $self = shift;
    my $dbh  = shift;
    my $attr = ( ref $_[0] eq 'HASH') ? $_[0] : {
        'UK_TABLE_SCHEM' => $_[1],'UK_TABLE_NAME' => $_[2]
            ,'FK_TABLE_SCHEM' => $_[4],'FK_TABLE_NAME' => $_[5] };

    if (!$self->{_constraint_cache}) {
        return unless $self->build_constraint_cache($dbh, $attr);
    }

    my @constraints = grep {
                          ($_->{CONSTRAINT_TYPE} eq 'R') &&
                          ($_->{R_CONSTRAINT_NAME}) &&
                          ($_->{OWNER} eq $attr->{FK_TABLE_SCHEM}) &&
                          ($_->{TABLE_NAME} eq $attr->{FK_TABLE_NAME})
                      }
                      @{$self->{_constraint_cache}->{constraints}};

    for my $constraint (@constraints) {
        next if $constraint->{columns};

        my ($foreign_table) = map { $_->{TABLE_NAME} }
                              grep {
                                  ($_->{CONSTRAINT_TYPE} eq 'P' || $_->{CONSTRAINT_TYPE} eq 'U') &&
                                  $_->{OWNER} eq $constraint->{R_OWNER} &&
                                  $_->{CONSTRAINT_NAME} eq $constraint->{R_CONSTRAINT_NAME} &&
                                  ($attr->{UK_TABLE_NAME} ? ($_->{TABLE_NAME} eq $attr->{UK_TABLE_NAME}) : 1)
                              } @{$self->{_constraint_cache}->{constraints}};

        my @fk_columns = sort {$a->{POSITION} <=> $b->{POSITION}}
                         map {
                             +{
                                 foreign_table => $foreign_table,
                                 %$_
                             }
                         }
                         grep {
                             $_->{OWNER} eq $attr->{FK_TABLE_SCHEM} &&
                             $_->{CONSTRAINT_NAME} eq $constraint->{CONSTRAINT_NAME}
                         }
                         @{$self->{_constraint_cache}->{columns}};

        for my $fk_column (@fk_columns) {
            next if $fk_column->{foreign_column};
            ($fk_column->{foreign_column}) = map { $_->{COLUMN_NAME} }
                                             grep {
                                                 $_->{OWNER} eq $constraint->{R_OWNER} &&
                                                 $_->{CONSTRAINT_NAME} eq $constraint->{R_CONSTRAINT_NAME} &&
                                                 $_->{POSITION} eq $fk_column->{POSITION}
                                             }
                                             @{$self->{_constraint_cache}->{columns}};
        }

        $constraint->{columns} = \@fk_columns;
    }

    my @final_constraints = map {
                                my $constraint = $_;
                                +{
                                    table => $constraint->{columns}[0]->{foreign_table},
                                    keys  => [map {$_->{COLUMN_NAME}} @{$constraint->{columns}}],
                                    refs  => [map {$_->{foreign_column}} @{$constraint->{columns}}],
                                }
                            }
                            @constraints;

    return \@final_constraints;
}

1;
