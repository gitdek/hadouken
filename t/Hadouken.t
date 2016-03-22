use strict;

#use Test::More qw(no_plan);

use Test::More;                                 # qw(no_plan);

diag("Performing Hadouken tests");

BEGIN {
    use_ok('Hadouken');
}

can_ok( 'Hadouken', ('new') );

diag("Testing Hadouken $Hadouken::VERSION, Perl $], $^X");

done_testing();
