use inc::Module::Install;

name 'Data-ObjectMapper';
perl_version '5.008001';
all_from 'lib/Data/ObjectMapper.pm';
license 'perl';

requires 'Scalar::Util';
requires 'Carp::Clan'       => 0;
requires 'DBI'              => 1.40;

requires 'DBIx::Connector';
requires 'Try::Tiny';
requires 'Class::MOP';
requires 'Clone';
requires 'Class::Data::Inheritable';
requires 'Data::Page' => 2.00;
requires 'Class::Accessor::Fast';
requires 'Hash::Merge';
requires 'Params::Validate';
requires 'Log::Any';
requires 'Digest::MD5';
requires 'Text::Balanced';
requires 'List::MoreUtils';
requires 'DateTime';

test_requires 'DBD::SQLite'         => 1.14;
test_requires 'DateTime::Format::SQLite';
test_requires 'Test::Builder'       => 0.33;
test_requires 'Test::Exception'     => 0;
test_requires 'Test::Base';
test_requires 'Test::Warn'          => 0.11;

recommends 'DateTime::Format::Pg';
recommends 'DateTime::Format::MySQL';
tests "t/*.t t/*/*.t";


auto_install;
WriteAll;
