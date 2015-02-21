#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: test-ircparse.pl
#
#        USAGE: ./test-ircparse.pl  
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
#      CREATED: 06/13/2014 11:37:24 PM
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use utf8;



use IRC::Utils ':ALL';




my $banmask = '*!*menace@*.org';
my $full_banmask = normalize_mask($banmask);

warn $full_banmask;

my $test = normalize_mask('menace@evilbinaries.org');

warn $test;
if (matches_mask($full_banmask,$test)) {
    warn "EEK!";
}


