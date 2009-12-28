package Data::ObjectMapper::Session::Cache;
use strict;
use warnings;

sub new { bless +{}, $_[0] }

sub set { $_[0]->{$_[1]} = $_[2] }

sub get { $_[0]->{$_[1]} }

sub remove { delete $_[0]->{$_[1]} }

1;
