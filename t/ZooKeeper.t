#!/usr/bin/env perl

use strict;
use warnings;

#BEGIN { eval "use blib" }
use v5.14;

use Test::More;

BEGIN { use_ok('Hadouken::ZooKeeper') }

diag("Testing Hadouken::ZooKeeper $Hadouken::ZooKeeper::VERSION, Perl $], $^X");

my $zk = new_ok( 'Hadouken::ZooKeeper' => [ zk_servers => 'localhost:2181' ] );

# $zk->_start();

done_testing();
