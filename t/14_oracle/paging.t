use strict;
use warnings FATAL => 'all';
use Test::More;
use DBIx::ObjectMapper::SQL;

#-- Regular query
my $query = DBIx::ObjectMapper::SQL->select
                ->column(['g', 'h'], 'i')
                ->from(['foo', 'f'])
                ->where(['x', '=', 'something'])
                ->limit(10)
                ->offset(4);

is_deeply(
    [$query->as_sql],
    ["SELECT g AS h, i FROM foo AS f WHERE ( x = ? ) LIMIT 4, 10", 'something'],
    'Default select statement format'
);


#-- Now we give it the Oracle flavor
$query->{driver} = 'Oracle';

is_deeply(
    [$query->as_sql],
    ["SELECT h, i FROM ( " .
         "SELECT /*+ first_row */ rownum AS oracle_rownum_XYZZY, h, i FROM ( " .
             "SELECT g h, i FROM foo f WHERE ( x = ? ) " .
         ") " .
     ") WHERE oracle_rownum_XYZZY >= 4 AND oracle_rownum_XYZZY <= 13",
     'something'],
    'Oracle select statement format'
);


#-- No limits regular
$query = DBIx::ObjectMapper::SQL->select
                ->column(['g', 'h'], ['i'])
                ->from(['foo', 'f'])
                ->where(['x', '=', 'something']);

is_deeply(
    [$query->as_sql],
    ["SELECT g AS h, i FROM foo AS f WHERE ( x = ? )", 'something'],
    'Default no limits select statement format'
);


#-- No limits Oracle
$query->{driver} = 'Oracle';

is_deeply(
    [$query->as_sql],
    ["SELECT g h, i FROM foo f WHERE ( x = ? )", 'something'],
    'Oracle no limits select statement format'
);


done_testing;

