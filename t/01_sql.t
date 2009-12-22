use Test::Base;
plan tests => ( 1 * blocks ) + 18;

use Data::ObjectMapper::SQL;

sub as_sql {
    my $param = shift;
    my ($sql, @bind) = $param->as_sql;
    return $sql . ' <= ' . join(',', @bind);
}

filters {
    input   => [qw(eval as_sql chomp)],
    expected => [qw(chomp)]
};

run_is;

{
    my $input = {
        column => [ 'customer_id', [ { count => 'order_id' }, 'cnt' ] ],
        from => [ [ 'order_mst' => 'orders' ] ],
        join => [
            [qw(order_goods_dtl order_id left)],
            [   'order_goods',
                [ [ 'order_goods.order_id' => \'order_mst.order_id' ], ],
                'left',
            ]
        ],
        where => [
            [   'order_insdate', 'between',
                [ '2008-01-01 00:00:00', '2009-01-01 00:00:00' ]
            ],
            [ 'order_status', 'not in', [ 1, 2, 3, 4 ] ],
            [ 'name', 'not like', '%hoge%' ],
        ],
        group_by => 'customer_id',
        order_by => 'customer_id',
        limit    => 10,
        offset   => 20,
        having   => [ [ { 'count' => 'order_id' }, '>', '1' ], ],
        driver   => 'Pg',
    };
    my $sql = Data::ObjectMapper::SQL->select(%$input);
    $input = { %$sql };

    my $clone = $sql->clone;
    is_deeply { %$clone }, $input;
    ok $clone != $input, "$clone != $input";

    for my $meth ( keys %$input ) {
        next if $meth eq 'driver';
        is_deeply $sql->$meth, $clone->$meth;
        if( ref $sql->{$meth} ) {
            isnt $sql->{$meth}, $clone->{$meth};
        }
    }
};


__END__
=== SELECT1
--- input
Data::ObjectMapper::SQL->select(
   column => [ 'customer_id', [ { count => 'order_id' }, 'cnt' ] ],
   from   => [ ['order_mst' => 'orders'] ],
   join  => [
       [qw(order_goods_dtl order_id left)],
       [
           'order_goods',
           [
               [ 'order_goods.order_id' => \'order_mst.order_id' ],
           ],
           'left',
       ]
   ],
   where => [
       [ 'order_insdate', 'between', [
           '2008-01-01 00:00:00',
           '2009-01-01 00:00:00'
       ]],
       [ 'order_status', 'not in', [1,2,3,4] ],
       [ 'name', 'not like', '%hoge%' ],
   ],
   group_by => 'customer_id',
   order_by => 'customer_id',
   limit => 10,
   offset => 20,
   having => [
       [ { 'count' => 'order_id' }, '>', '1' ],
   ],
   driver => 'Pg',
);
--- expected
SELECT customer_id, COUNT(order_id) AS cnt FROM order_mst AS orders LEFT JOIN order_goods_dtl USING(order_id) LEFT JOIN order_goods ON ( order_goods.order_id = order_mst.order_id ) WHERE ( order_insdate BETWEEN ? AND ? AND order_status NOT IN (?,?,?,?) AND name NOT LIKE ? ) GROUP BY customer_id HAVING ( COUNT(order_id) > ? ) ORDER BY customer_id LIMIT 10 OFFSET 20 <= 2008-01-01 00:00:00,2009-01-01 00:00:00,1,2,3,4,%hoge%,1

=== SELECT2
--- input
my $sql = Data::ObjectMapper::SQL->select()
->column ( qw(a b c d) )
->where(
        [ 'a' , '=', 1 ],
        [ { sum => 'd' }, '>', 100 ],
        [  'text', '@@', 'hogefuga' ]
)
->limit(100)
->offset(2)
->order_by('hogehoge desc');

$sql->add_column({ sum => 'd' });
$sql->add_from( 'table' );
$sql->add_where(
        {
            or => [
                [ 'c', '=', 1 ],
                [ d => 2 ],
            ]
        }
);
$sql->add_order_by('fugafuga');

return $sql;
--- expected
SELECT a, b, c, d, SUM(d) FROM table WHERE ( a = ? AND SUM(d) > ? AND text @@ ? AND ( c = ? OR d = ? ) ) ORDER BY hogehoge desc, fugafuga LIMIT 2, 100 <= 1,100,hogefuga,1,2

=== INSERT
--- input
Data::ObjectMapper::SQL->insert(
    table => 'hoge',
    values => {
        a => 1,
        b => 2,
        c => 3,
        d => 4,
    }
);
--- expected
INSERT INTO hoge ( a, b, c, d ) VALUES (?,?,?,?) <= 1,2,3,4

=== INSERT SELECT
--- input
Data::ObjectMapper::SQL->insert()
->table('hoge')
->values(
    [ qw(a b c d) ] => Data::ObjectMapper::SQL->select
                    ->from('hoge2')
                    ->where(
                        [ a => 1 ],
                        [ b => 2 ],
                    )
);
--- expected
INSERT INTO hoge ( a, b, c, d ) SELECT * FROM hoge2 WHERE ( a = ? AND b = ? ) <= 1,2

=== INSERT SELECT add
--- input
my $sql = Data::ObjectMapper::SQL->insert();
$sql->add_table('hoge');
$sql->add_values(
    [ qw(a b c d) ] => Data::ObjectMapper::SQL->select
                    ->from('hoge2')
                    ->where(
                        [ a => 1 ],
                        [ b => 2 ],
                    )
);
return $sql;
--- expected
INSERT INTO hoge ( a, b, c, d ) SELECT * FROM hoge2 WHERE ( a = ? AND b = ? ) <= 1,2

=== INSERT MULTI
--- input
Data::ObjectMapper::SQL->insert()
->table('hoge')
->values(
    [ qw(a b c d) ],
    [ qw(1 2 3 4) ],
    [ qw(5 6 7 8) ],
    [ qw(9 10 11 12) ],
);
--- expected
INSERT INTO hoge ( a, b, c, d ) VALUES (?,?,?,?), (?,?,?,?), (?,?,?,?) <= 1,2,3,4,5,6,7,8,9,10,11,12

=== INSERT MULTI ADD
--- input
my $sql = Data::ObjectMapper::SQL->insert();
$sql->add_table('hoge');
$sql->add_values(
    [ qw(a b c d) ],
    [ qw(1 2 3 4) ],
    [ qw(5 6 7 8) ],
    [ qw(9 10 11 12) ],
);
return $sql;
--- expected
INSERT INTO hoge ( a, b, c, d ) VALUES (?,?,?,?), (?,?,?,?), (?,?,?,?) <= 1,2,3,4,5,6,7,8,9,10,11,12

=== INSERT ADD
--- input
my $sql = Data::ObjectMapper::SQL->insert();
$sql->table('foo');
$sql->values( a => 1, b => 2 );
$sql->add_values( c => 3 );

return $sql;
--- expected
INSERT INTO foo ( a, b, c ) VALUES (?,?,?) <= 1,2,3

=== UPDATE
--- input
Data::ObjectMapper::SQL->update(
    table => 'foo',
    set   => {
         a => 1,
         b => 2,
    },
    where => [
        [ c => 1 ],
    ]
);
--- expected
UPDATE foo SET a = ? , b = ? WHERE ( c = ? ) <= 1,2,1

=== UPDATE ADD
--- input
my $sql = Data::ObjectMapper::SQL->update;
$sql->table('foo');
$sql->set( a => 1 );
$sql->where( [qw(c 1)] );

$sql->add_set( b => 2 );
$sql->add_where( [ d => q(hoge) ] );

return $sql;
--- expected
UPDATE foo SET a = ? , b = ? WHERE ( c = ? AND d = ? ) <= 1,2,1,hoge

=== UPDATE CHAIN
--- input
Data::ObjectMapper::SQL->update->table('foo')->set( a => 1 )->where( [qw(c 1)] );
--- expected
UPDATE foo SET a = ? WHERE ( c = ? ) <= 1,1

=== DELETE
--- input
Data::ObjectMapper::SQL->delete(
    table => 'bar',
    where => [
        [ qw(a 1) ],
        [ qw(b 2) ],
    ]
);
--- expected
DELETE FROM bar WHERE ( a = ? AND b = ? ) <= 1,2

=== DELETE ADD
--- input
my $sql = Data::ObjectMapper::SQL->delete()->where([ qw(a 1) ]);
$sql->add_table('bar');
$sql->add_where(
    [ qw(b 2) ],
);
--- expected
DELETE FROM bar WHERE ( a = ? AND b = ? ) <= 1,2

=== SELECT JOIN
--- input
Data::ObjectMapper::SQL->select(
    from => 'hoge',
    join  => [
       [
           'order_goods',
           [
               [ 'order_goods.order_id', 1 ],
           ],
           'left',
       ]
   ],
   where =>[ [ qw( a 2 ) ] ]
);
--- expected
SELECT * FROM hoge LEFT JOIN order_goods ON ( order_goods.order_id = ? ) WHERE ( a = ? ) <= 1,2

=== ARRAY SELECT FOR PG
--- input
Data::ObjectMapper::SQL->select(
    from => 'array_test',
    where => [ [ 'a', \[ 1, 2 ] ] ]
);
--- expected
SELECT * FROM array_test WHERE ( a = ? ) <= {1,2}

=== ARRAY INSERT FOR PG
--- input
Data::ObjectMapper::SQL->insert->table('array_test')->values( id => 1, array_field => [1,2]);
--- expected
INSERT INTO array_test ( array_field, id ) VALUES (?,?) <= {1,2},1

=== ARRAY UPDATE FOR PG
--- input
Data::ObjectMapper::SQL->update->table('array_test')->set( array_field => [1,2] )->where( [ 'array_field', \[ 2, 3 ] ] );
--- expected
UPDATE array_test SET array_field = ? WHERE ( array_field = ? ) <= {1,2},{2,3}

=== UNION
--- input
Data::ObjectMapper::SQL->union(
    driver => 'Pg',
    sets => [
       Data::ObjectMapper::SQL->select(
         from => 'table1',
         column => [qw(id name)],
         where => [[qw(id 1)]],
       ),
       Data::ObjectMapper::SQL->select(
         from => 'table2',
         column => [qw(id name)],
         where => [[qw(id 1)]],
       ),
       Data::ObjectMapper::SQL->select(
         from => 'table3',
         column => [qw(id name)],
         where => [[qw(id 1)]],
       ),
    ],
    order_by => [qw(id)],
    group_by => [qw(id)],
    limit    => 10,
    offset   => 100,
);
--- expected
( SELECT id, name FROM table1 WHERE ( id = ? ) ) UNION ( SELECT id, name FROM table2 WHERE ( id = ? ) ) UNION ( SELECT id, name FROM table3 WHERE ( id = ? ) ) GROUP BY id ORDER BY id LIMIT 10 OFFSET 100 <= 1,1,1

=== UNION Chain
--- input
Data::ObjectMapper::SQL->new('Pg')->union->sets(
       Data::ObjectMapper::SQL->select(
         from => 'table1',
         column => [qw(id name)],
         where => [[qw(id 1)]],
       ),
       Data::ObjectMapper::SQL->select(
         from => 'table2',
         column => [qw(id name)],
         where => [[qw(id 1)]],
       ),
       Data::ObjectMapper::SQL->select(
         from => 'table3',
         column => [qw(id name)],
         where => [[qw(id 1)]],
       ),
)->order_by('id')->group_by('id')->limit(10)->offset(100);

--- expected
( SELECT id, name FROM table1 WHERE ( id = ? ) ) UNION ( SELECT id, name FROM table2 WHERE ( id = ? ) ) UNION ( SELECT id, name FROM table3 WHERE ( id = ? ) ) GROUP BY id ORDER BY id LIMIT 10 OFFSET 100 <= 1,1,1

