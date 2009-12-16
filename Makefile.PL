use inc::Module::Install;

name 'Data-ObjectMapper';
perl_version '5.008001';
all_from 'lib/Data/ObjectMapper.pm';
license 'perl';


requires 'Scalar::Util';
requires 'Carp::Clan'       => 0;
requires 'DBI'              => 1.40;
requires 'Class::Inspector' => 0;
requires 'Text::Balanced';
requires 'Encode' => 0;
requires 'DBIx::Connector';
requires 'Try::Tiny';
requires 'Class::MOP';

#requires 'Data::Page' => 2.00;

#requires 'Storable'         => 0;
#requires 'Class::Accessor::Fast';
#requires 'Module::Pluggable::Object';
#requires 'List::MoreUtils';
#requires 'DateTime';
#requires 'FormValidator::Simple';
#requires 'Log::Log4perl';
#requires 'Cache::Cache';
#requires 'UNIVERSAL::isa';

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
