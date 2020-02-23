#!/usr/bin/env perl

use strict;
use warnings;

use v5.14;

use Test::More;                                 # qw(no_plan);

BEGIN {
    use_ok('Hadouken::Plugin::ExamplePlugin');
    use_ok('Hadouken::Plugin::StockMarket');
    use_ok('Hadouken::Plugin::IMDB');
    use_ok('Hadouken::Plugin::Portfolio');
    use_ok('Hadouken::Plugin::Translate');
    use_ok('Hadouken::Plugin::Shorten');
    use_ok('Hadouken::Plugin::MitchQuotes');
    use_ok('Hadouken::Plugin::Whois');
    use_ok('Hadouken::Plugin::UrbanDictionary');
    use_ok('Hadouken::Plugin::GeoIP');
    use_ok('Hadouken::Plugin::IPCalc');
    use_ok('Hadouken::Plugin::MagicEight');
} ## ---------- end BEGIN

# can_ok('Hadouken::Plugin::IMDB', ('new'));

diag("Testing Plugins for Hadouken $Hadouken::VERSION, Perl $], $^X");

done_testing();

