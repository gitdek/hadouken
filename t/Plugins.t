use strict;

use Test::More qw(no_plan);

BEGIN {
    use_ok('Hadouken::Plugin::StockMarket');
    use_ok('Hadouken::Plugin::Weather');
    use_ok('Hadouken::Plugin::IMDB');
    use_ok('Hadouken::Plugin::Dictionary');
    use_ok('Hadouken::Plugin::Shorten');
} ## ---------- end BEGIN

# can_ok('Hadouken::Plugin::StockMarket', ('new'));

diag("Testing Plugins for Hadouken $Hadouken::VERSION, Perl $], $^X");

#diag( "Testing Hadouken::Plugin::StockMarket $Hadouken::Plugin::StockMarket::VERSION, Perl $], $^X" );

done_testing();

