package Data::ObjectMapper::Session;
use strict;
use warnings;
use Carp::Clan;
use Scalar::Util qw(refaddr);
use Data::ObjectMapper::Utils;
use Data::ObjectMapper::Session::Query;
my $DEFAULT_QUERY_CLASS = 'Data::ObjectMapper::Session::Query';

sub new {
    my $class = shift;
    my %attr = @_;

    my $self = bless {
        query_class  => $attr{query_class} || $DEFAULT_QUERY_CLASS,
        queries      => +{},
    }, $class;

    return $self;
}

sub query_class { $_[0]->{query_class} }

sub query {
    my $self = shift;
    my $target_class = shift;
    $self->{queries}{$target_class}
        ||= $self->query_class->new( $target_class );
    $self->{queries}{$target_class};
}

sub add {

}

sub add_all {

}

sub is_modified {
    my ( $self, $obj ) = @_;

    my $query = $self->query(ref($obj));
    return unless $query->is_persistent($obj);

    my $reduce_data   = $obj->__mapper__->reducing($obj);
    my $original_data = $query->get_original_data($obj);
    if (grep { $reduce_data->{$_} ne $original_data->{$_} } keys %$reduce_data)
    {
        return 1;
    }
    else {
        return 0;
    }
}

sub save_or_update {
    my $self = shift;
    my $obj  = shift;

    my $query  = $self->query(ref($obj));
    if( $query->is_persistent($obj) ) {

    }
    elsif( $query->is_detached($obj) ) {
        confess "$obj has detached from this session.";
    }
    else {

    }
}

sub save {
    my $self = shift;
    my $obj  = shift;

    my $query  = $self->query(ref($obj));
    confess "XXXX" if $query->is_persistent($obj);

    my $mapper = $obj->__mapper__;
    my $reduce_data = $mapper->reducing($obj);
    my $comp_result
        = $mapper->from->insert->values(%$reduce_data)->execute();
    # XXXX
    # mappingじゃなくて、setterへremappingのほうがいいね。
    my $new_obj = $mapper->mapping($comp_result);
    $query->attach( $new_obj, $comp_result );
    return $new_obj;
}

sub update {
    my $self = shift;
    my $obj  = shift;

    my $query  = $self->query(ref($obj));
    confess "XXXX" unless $query->is_persistent($obj);

    my $mapper = $obj->__mapper__;
    my $reduce_data = $mapper->reducing($obj);

    my $original_data = $query->get_original_data($obj);
    my %modified_data = map { $_ => $reduce_data->{$_} }
        grep { $reduce_data->{$_} ne $original_data->{$_} }
            keys %$reduce_data;

    confess "" unless %modified_data;

    my $uniq_cond = $query->get_identity_condition($obj);
    my $r = $mapper->from->update->set(%modified_data)->where(@$uniq_cond)
        ->execute();
    # ------
    # updateされた場合に、db側で自動でtriggerとかいろいろあった場合に
    # コンフリクトすることもあるだろうから
    # update後はdetach扱いのほうがいいと思う
    # ------
    $query->detach( $obj, $original_data );

    # XXXX
    # setterへremappingのほうがいいね。
    return $r;
}

sub delete {
    my $self = shift;
    my $obj  = shift;

    my $query  = $self->query(ref($obj));
    confess "XXXX" unless $query->is_persistent($obj);

    my $mapper = $obj->__mapper__;
    my $uniq_cond = $query->get_identity_condition($obj);
    $mapper->from->delete->where(@$uniq_cond)->execute();
    $query->detach( $obj );
}

sub detach {
    my $self = shift;
    my $obj  = shift;
    $self->query(ref($obj))->detach($obj);
}

1;
