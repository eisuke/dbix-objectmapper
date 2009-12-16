use strict;
use warnings;
use Test::More;
use Test::Exception;
use Encode;

use Data::ObjectMapper::Metadata::Table::Column;

my $c = Data::ObjectMapper::Metadata::Table::Column->new(
    {   name        => 'type',
        sep         => '.',
        table       => 'b',
        type        => 'text',
        size        => undef,
        is_nullable => 1,
        validation  => undef,
        on_update   => sub { '-on_update' },
        default     => sub { '-default' },
        utf8        => 1,
        readonly    => undef,
        inflate     => sub { $_[0] . '-inflate' },
        deflate     => sub { $_[0] . '-deflate' },
    }
);

{ # basic
    is $c->name, 'type', 'get name';
    is $c->sep, '.', 'get sep';
    is $c->table, 'b', 'get table';
    is $c, 'b.type', 'to_string';
};

{ # oprator
    is_deeply $c->op('%%', 'opcheck'), [ 'b.type', '%%', 'opcheck'], 'custom operator';
    is_deeply $c->eq('eqcheck'), [ 'b.type', '=', 'eqcheck'], 'eq';

    is_deeply $c == 'a', [ 'b.type', '=', 'a' ], '==';
    is_deeply $c !=  1 , [ 'b.type', '!=', 1 ], '!=';
    is_deeply $c <=  2 , [ 'b.type', '<=', 2 ], '<=';
    is_deeply $c >=  3 , [ 'b.type', '>=', 3 ], '>=';
    is_deeply $c >   4 , [ 'b.type', '>', 4 ], '>';
    is_deeply $c <   5 , [ 'b.type', '<', 5], '<';
    is_deeply $c->between(1, 2), [ 'b.type', 'BETWEEN', [1 , 2 ]], 'between';
    is_deeply $c->in(1,2,3,4), [ 'b.type', 'IN', [1 ,2 ,3 ,4] ], 'IN';
    is_deeply $c->not_in(1,2,3,4), [ 'b.type', 'NOT IN', [1 ,2 ,3 ,4] ], 'NOT IN';
    is_deeply $c->like('%Led%'), [ 'b.type', 'LIKE', '%Led%'], 'LIKE';
    is_deeply $c->not_like('%Led%'), [ 'b.type', 'NOT LIKE', '%Led%'], 'NOT LIKE';

    is $c->desc, 'b.type DESC', 'DESC';

    is_deeply $c->as('t'), [ 'b.type', 't' ], 'as(to_array)';
    is_deeply { $c->is('b') }, { 'type' => 'b' }, 'is(hash)';
    is_deeply { $c->is(undef) } , { 'type' => undef }, 'is(undef)';
};

{ # property
    is $c->type, 'text', 'property type';
    is $c->size, undef, 'property size';
    is $c->is_nullable, 1, 'property is_nullable';
};

{ # from/to_storage
    use utf8;
    is $c->from_storage('あ'), 'あ-inflate', 'from_storage';
    is $c->to_storage(), '-default-deflate', 'to_storage default';
    is $c->to_storage('い'), Encode::encode('utf8', 'い-deflate'), 'to_stroage utf8';
    is $c->to_storage_on_update(), '-on_update-deflate', 'to_storage_on_update';
};

{ # vaidation

    $c = Data::ObjectMapper::Metadata::Table::Column->new(
        {   name        => 'type',
            sep         => '.',
            table       => 'b',
            type        => 'text',
            size        => undef,
            is_nullable => 1,
            validation  => sub { $_[0] =~ /^\d+$/ },
            on_update   => undef,
            default     => undef,
            utf8        => undef,
            readonly    => undef,
            inflate     => undef,
            deflate     => undef,
        }
    );

    ok $c->validation->(1), 'do validation';
    ok !$c->validation->('a'), 'do vlaidation';
    dies_ok { $c->to_storage('foo') } 'to_storage invalid';
    is $c->to_storage(2), 2, 'to_storage valid';
};

{ # readonly
    $c = Data::ObjectMapper::Metadata::Table::Column->new(
        {   name        => 'type',
            sep         => '.',
            table       => 'b',
            type        => 'text',
            size        => undef,
            is_nullable => 1,
            validation  => undef,
            on_update   => undef,
            default     => undef,
            utf8        => undef,
            readonly    => 1,
            inflate     => undef,
            deflate     => undef,
        }
    );

    ok $c->readonly, 'readonly';
    ok $c->to_storage('str'), 'readonly to_storage';
    dies_ok { $c->to_storage_on_update('str') } 'readonly to_storage_on_update';
};


done_testing;
