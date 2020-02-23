#!/usr/bin/env perl

use strict;
use warnings;

use v5.14;

use Test::More qw(no_plan);

BEGIN {
    use_ok('Hadouken');
}

can_ok( 'Hadouken', ('new') );

diag("Testing Hadouken $Hadouken::VERSION, Perl $], $^X");

_
