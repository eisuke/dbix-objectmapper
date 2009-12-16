package Data::ObjectMapper::Engine::DBI::Driver::mysql;
use strict;
use warnings;
use base qw(Data::ObjectMapper::Engine::DBI::Driver);

sub init {
    my $self = shift;

    eval "use DateTime::Format::MySQL";
    $self->log->exception("Couldn't load DateTime::Format::MySQL: $@") if $@;
    $self->{datetime_parser} ||= 'DateTime::Format::MySQL';
}

sub last_insert_id {
    my ( $self, $dbh, $table, $column ) = @_;
    $dbh->{mysql_insertid};
}

sub get_primary_key {
    my $self = shift;
    return @{$self->_mysql_table_get_keys(@_)->{PRIMARY}};
}

sub get_table_uniq_info {
    my $self = shift;

    my @uniqs;
    my $keydata = $self->_mysql_table_get_keys(@_);
    foreach my $keyname (keys %$keydata) {
        next if $keyname eq 'PRIMARY';
        push(@uniqs, [ $keyname => $keydata->{$keyname} ]);
    }
    return \@uniqs;
}

#  mostly based on DBIx::Class::Schema::Loader::DBI::mysql
sub _mysql_table_get_keys {
    my ($self, $dbh, $table) = @_;

    if(!exists($self->{_cache}->{_mysql_keys}->{$table})) {
        my %keydata;
        my $sth = $dbh->prepare("SHOW INDEX FROM `$table`");
        $sth->execute;
        while(my $row = $sth->fetchrow_hashref) {
            next if $row->{Non_unique};
            push(@{$keydata{$row->{Key_name}}},
                [ $row->{Seq_in_index}, lc $row->{Column_name} ]
            );
        }
        foreach my $keyname (keys %keydata) {
            my @ordered_cols = map { $_->[1] } sort { $a->[0] <=> $b->[0] }
                @{$keydata{$keyname}};
            $keydata{$keyname} = \@ordered_cols;
        }
        $self->{_cache}->{_mysql_keys}->{$table} = \%keydata;
    }

    return $self->{_cache}->{_mysql_keys}->{$table};
}

1;
