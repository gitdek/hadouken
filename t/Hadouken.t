use strict;

use Test::More qw(no_plan);
# use Test::More;                                 # qw(no_plan);

BEGIN {
    use_ok('Hadouken');
}

can_ok( 'Hadouken', ('new') );

diag("Testing Hadouken $Hadouken::VERSION, Perl $], $^X");

_
