#!/usr/bin/perl

use threads;
use Nmap::Scanner;

use strict;
my $scanner = Nmap::Scanner->new();
$Nmap::Scanner::DEBUG = 1;
my $hosts = $ARGV[0] ||
die "Missing host spec (e.g. localhost)\n$0 host_spec port_spec\n";

my $last_progress = time;
my $running = 0;
my $ports = $ARGV[1] ||
die "Missing port spec (e.g. 1-1024)\n$0 host_spec port_spec\n";
$scanner->register_scan_complete_event(\&scan_complete);
$scanner->register_scan_started_event(\&scan_started);
$scanner->register_port_found_event(\&port_found);
$scanner->register_no_ports_open_event(\&no_ports);


$running = 1;
$scanner->add_scan_port($ports);
#$scanner->add_scan_port(8080);
$scanner->guess_os();
$scanner->max_rtt_timeout("300ms");
$scanner->add_target($hosts);

my $thr1 = async { $scanner->scan(); }; #"-sT -P0 -O --max_rtt_timeout 300ms -p $ports $hosts"); };

print "Blocking?\n";
#$thr1->join();
while ($running && $thr1->is_running()) {
    if((time() - $last_progress) > 2) {
        print "Scan of $hosts in progress...\n";
    }
    sleep(1);
}

if ($thr1->is_joinable()) {
$thr1->join();
}

sub no_ports {
    my $self = shift;
    my $host = shift;
    my $extraports = shift;
    my $name = $host->hostname();
    my $addresses = join(',', map {$_->addr()} @{$host->addresses()});
    my $state = $extraports->state();
    print "All ports on host $name ($addresses) are in state $state\n";
}

sub scan_complete {
    my $self = shift;
    my $host = shift;
# print $host->as_xml();
    $running = 0;
    print "Finished scanning ", $host->hostname(),":\n";
    my $guess = $host->os();
    if ($guess) {
        my @matches = $host->os()->osmatches();
        #my $uptime = $guess->uptime;
        #print " * Host has been up since " . $uptime->lastboot() . "\n"
        #if (defined($uptime) && $uptime->lastboot() ne '');
        #my $t = $guess->tcpsequence();
        #print " * TCP Sequence difficulty: " . $t->difficulty(),"\n"
        #if $t->difficulty();
        if (scalar(@matches) > 0) {
            print " * OS guesses:\n";
            for my $match (@matches) {
                print "   - " . $match->name() . " / (".
                $match->accuracy() . "% sure)\n";
            }
        }
    } else {
        print "Can't figure out what OS ",$host->hostname()," has.\n";
    }
}

sub scan_started {
    my $self = shift;
    my $host = shift;
    my $hostname = $host->hostname();
    my $addresses = join(',', map {$_->addr()} $host->addresses());
    my $status = $host->status();
    print "$hostname ($addresses) is $status\n";
}

sub port_found {
    my $self = shift;
    my $host = shift;
    my $port = shift;
    
    return if $port->state() eq 'closed';

    my $name = $host->hostname();
    my $addresses = join(',', map {$_->addr()} $host->addresses());
    print "On host $name ($addresses), found ",
    $port->state()," port ",
    join('/',$port->protocol(), $port->portid()),"\n";
    # sleep(1);
    $last_progress = time;
}


