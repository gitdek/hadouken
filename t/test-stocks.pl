
#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: test-stocks.pl
#
#        USAGE: ./test-stocks.pl  
#
#  DESCRIPTION: 
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: YOUR NAME (), 
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 06/12/2014 11:18:50 AM
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use utf8;

use Finance::Quote;

my $arg = 'goog';

my $q = Finance::Quote->new();
my %data = $q->fetch('nyse', $arg);
if ($data{$arg, 'success'}) {

    my $summary = $data{$arg, 'name'} ." Price: ". $data{$arg, 'price'} ." Volume: ".$data{$arg, 'volume'}." High: ".$data{$arg, 'high'}." Low: ".$data{$arg, 'low'};

    warn $summary;
}
