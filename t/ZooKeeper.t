#!/usr/bin/env perl

BEGIN { eval "use blib" }

use strict;
use warnings;

use v5.14;

use Test::More;

BEGIN { use_ok('Hadouken::ZooKeeper') }

diag("Testing Hadouken::ZooKeeper $Hadouken::ZooKeeper::VERSION, Perl $], $^X");

my $zk = new_ok( 'Hadouken::ZooKeeper' => [ zk_servers => 'localhost:2181' ] );

$zk->connect();

done_testing();
