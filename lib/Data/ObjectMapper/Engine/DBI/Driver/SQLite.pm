package Data::ObjectMapper::Engine::DBI::Driver::SQLite;
use strict;
use warnings;
use Data::ObjectMapper::Utils;
use Text::Balanced qw( extract_bracketed );
use base qw(Data::ObjectMapper::Engine::DBI::Driver);

sub init {
    my $self = shift;
    $self->{_sqlite_parse_data} = {};
    eval "use DateTime::Format::SQLite";
    $self->log->exception("Couldn't load DateTime::Format::SQLite: $@") if $@;
    $self->{datetime_parser} ||= 'DateTime::Format::SQLite';
}

sub get_table_uniq_info {
    my ($self, $dbh, $table) = @_;

    $self->{_sqlite_parse_data}->{$table} ||=
        $self->_sqlite_parse_table($dbh, $table);

    return $self->{_sqlite_parse_data}->{$table}->{uniqs};
}

sub last_insert_id {
    my ( $self, $dbh, $table, $column ) = @_;
    $dbh->func('last_insert_rowid')
}

# XXX this really needs a re-factor
sub _sqlite_parse_table {
    my ($self, $dbh, $table) = @_;

    my @rels;
    my @uniqs;
    my %auto_inc;

    my $sth = $self->{_cache}->{sqlite_master}
        ||= $dbh->prepare(q{SELECT sql FROM sqlite_master WHERE tbl_name = ?});

    $sth->execute($table);
    my ($sql) = $sth->fetchrow_array;
    return { rels => +[], uniqs => +[], auto_inc => +{} } unless $sql;

    $sth->finish;

    # Cut "CREATE TABLE ( )" blabla...
    $sql =~ /^[\w\s']+\((.*)\)$/si;
    my $cols = $1;

    # strip single-line comments
    $cols =~ s/\-\-.*\n/\n/g;

    # temporarily replace any commas inside parens,
    # so we don't incorrectly split on them below
    my $cols_no_bracketed_commas = $cols;
    while ( my $extracted =
        ( extract_bracketed( $cols, "()", "[^(]*" ) )[0] )
    {
        my $replacement = $extracted;
        $replacement              =~ s/,/--comma--/g;
        $replacement              =~ s/^\(//;
        $replacement              =~ s/\)$//;
        $cols_no_bracketed_commas =~ s/$extracted/$replacement/m;
    }

    # Split column definitions
    for my $col ( split /,/, $cols_no_bracketed_commas ) {

        # put the paren-bracketed commas back, to help
        # find multi-col fks below
        $col =~ s/\-\-comma\-\-/,/g;

        $col =~ s/^\s*FOREIGN\s+KEY\s*//i;

        # Strip punctuations around key and table names
        $col =~ s/[\[\]'"]/ /g;
        $col =~ s/^\s+//gs;

        # Grab reference
        chomp $col;

        if($col =~ /^(.*)\s+UNIQUE/i) {
            my $colname = $1;
            $colname =~ s/\s+.*$//;
            push(@uniqs, [ "${colname}_unique" => [ lc $colname ] ]);
        }
        elsif($col =~/^\s*UNIQUE\s*\(\s*(.*)\)/i) {
            my $cols = $1;
            $cols =~ s/\s+$//;
            my @cols = map { lc } split(/\s*,\s*/, $cols);
            my $name = join(q{_}, @cols) . '_unique';
            push(@uniqs, [ $name => \@cols ]);
        }

        if ($col =~ /AUTOINCREMENT/i) {
            $col =~ /^(\S+)/;
            $auto_inc{lc $1} = 1;
        }

        next if $col !~ /^(.*\S)\s+REFERENCES\s+(\w+) (?: \s* \( (.*) \) )? /ix;

        my ($cols, $f_table, $f_cols) = ($1, $2, $3);

        if($cols =~ /^\(/) { # Table-level
            $cols =~ s/^\(\s*//;
            $cols =~ s/\s*\)$//;
        }
        else {               # Inline
            $cols =~ s/\s+.*$//;
        }

        my @cols = map { s/\s*//g; lc $_ } split(/\s*,\s*/,$cols); ## no critic
        my $rcols;
        if($f_cols) {
            my @f_cols = map { s/\s*//g; lc $_ } split(/\s*,\s*/,$f_cols); ## no critic
            Data::ObjectMapper::Utils::exception(
                "Mismatched column count in rel for $table => $f_table")
              if @cols != @f_cols;

            $rcols = \@f_cols;
        }
        push(@rels, {
            local_columns => \@cols,
            remote_columns => $rcols,
            remote_table => $f_table,
        });
    }

    return { rels => \@rels, uniqs => \@uniqs, auto_inc => \%auto_inc };
}

1;

