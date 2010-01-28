package Data::ObjectMapper::Engine::DBI::Driver::Pg;
use strict;
use warnings;
use Carp::Clan;
use Try::Tiny;
use base qw(Data::ObjectMapper::Engine::DBI::Driver);

sub init {
    my $self = shift;
    $self->{db_schema} ||= 'public';
    try {
        require DateTime::Format::Pg;
        DateTime::Format::Pg->import;
        $self->{datetime_parser} ||= 'DateTime::Format::Pg';
    } catch {
        confess("Couldn't load DateTime::Format::Pg: $_");
    };
}

# Copied from DBIx::Class::Schema::Loader::DBI::Pg
sub get_table_uniq_info {
    my $self = shift;
    my ($dbh, $table) = @_;

    # Use the default support if available
    if( $DBD::Pg::VERSION >= 1.50 ) {
        return $self->SUPER::get_table_uniq_info(@_);
    }

    my @uniqs;

    # Most of the SQL here is mostly based on
    #   Rose::DB::Object::Metadata::Auto::Pg, after some prodding from
    #   John Siracusa to use his superior SQL code :)

    my $attr_sth = $self->{_cache}->{pg_attr_sth} ||= $dbh->prepare(
        q{SELECT attname FROM pg_catalog.pg_attribute
        WHERE attrelid = ? AND attnum = ?}
    );

    my $uniq_sth = $self->{_cache}->{pg_uniq_sth} ||= $dbh->prepare(
        q{SELECT x.indrelid, i.relname, x.indkey
        FROM
          pg_catalog.pg_index x
          JOIN pg_catalog.pg_class c ON c.oid = x.indrelid
          JOIN pg_catalog.pg_class i ON i.oid = x.indexrelid
          JOIN pg_catalog.pg_constraint con ON con.conname = i.relname
          LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE
          x.indisunique = 't' AND
          c.relkind     = 'r' AND
          i.relkind     = 'i' AND
          con.contype   = 'u' AND
          n.nspname     = ? AND
          c.relname     = ?}
    );

    $uniq_sth->execute($self->db_schema, $table);
    while(my $row = $uniq_sth->fetchrow_arrayref) {
        my ($tableid, $indexname, $col_nums) = @$row;
        $col_nums =~ s/^\s+//;
        my @col_nums = split(/\s+/, $col_nums);
        my @col_names;

        foreach (@col_nums) {
            $attr_sth->execute($tableid, $_);
            my $name_aref = $attr_sth->fetchrow_arrayref;
            push(@col_names, $name_aref->[0]) if $name_aref;
        }

        if(!@col_names) {
            $self->log->warn(
                "Failed to parse UNIQUE constraint $indexname on $table");
        }
        else {
            push(@uniqs, [ $indexname => \@col_names ]);
        }
    }

    return \@uniqs;
}

sub last_insert_id {
    my ( $self, $dbh, $table, $column ) = @_;
    $dbh->last_insert_id( undef, undef, $table, $column );
}

sub set_time_zone_query {
    my ( $self ) = @_;
    my $tz = $self->time_zone;
    return "SET timezone TO $tz";
}

1;
