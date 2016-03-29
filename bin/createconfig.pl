#!/usr/bin/env perl

use strict;
use warnings;

use File::Copy qw (copy);

if(-e "example.hadouken.conf") {
	unless(-e $ARGV[0]) {
        print "copying example config to $ARGV[0]\n";
	    copy("./example.hadouken.conf", $ARGV[0]) or die $!;
    } else {
        print "config exists.. not copying\n";
    }
}

