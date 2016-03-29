#!/usr/bin/env perl

use strict;
use warnings;

use Cwd qw(abs_path getcwd);
use File::Basename;

print "Decompressing GeoIP databases...";
if ($ARGV[0] eq 'skip') {
	print "skipping!\n";
	exit 0;
} else {
	print "working.\n";
}

# print "argv0 is $ARGV[0]\n";


my $script_abs = abs_path($0);
my $script_dir = dirname($script_abs);
# print "script dir is $script_dir\n";

my $cwd = getcwd();
#print "current dir is $cwd\n";

chdir($script_dir) or die("Failed to change to directory: $!"); 
chdir "../data/geoip/" or die("Failed to change to directory: $!");

$cwd = getcwd();
# print "current dir is $cwd\n";
system("gzip -dq *.gz");

print "Finished decompressing.\n";
#my $geoip_gzip = "$path../data../geoip/";

exit 0;

