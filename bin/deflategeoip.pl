#!/usr/bin/perl

use strict;
use warnings;

use Cwd qw(abs_path getcwd);
use File::Basename;

print "Decompressing GeoIP databases...\n";


my $force_overwrite = $ARGV[0] || 0;

# print "$ARGV[0]\n";

my $script_abs = abs_path($0);
my $script_dir = dirname($script_abs);
# print "script dir is $script_dir\n";

my $cwd = getcwd();
#print "current dir is $cwd\n";

chdir($script_dir) or die("Failed to change to directory: $!");
chdir "../data/geoip/" or die("Failed to change to directory: $!");

$cwd = getcwd();
# print "current dir is $cwd\n";

if(defined $force_overwrite && $force_overwrite) {
	system("gzip -dqfk *.gz");
} else {
	system("echo no | gzip -dqk *.gz");
}

print "Finished decompressing.\n";

exit 0;

