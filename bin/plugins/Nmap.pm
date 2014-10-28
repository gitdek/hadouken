package Hadouken::Plugin::Nmap;

use strict;
use warnings;
#use diagnostics;
use threads;

use Nmap::Parser;
use String::IRC;
use Data::Printer alias => 'Dumper', colored => 1;
use TryCatch;

our $VERSION = '0.1';
our $AUTHOR = 'dek';

#our $start_time = time();
#our $closed_ports = 0;

# Description of this command.
sub command_comment {
    my $self = shift;
    return "perform nmap scan of host or by irc nick(which is then resolved)";
}

# Clean name of command.
sub command_name {
    my $self = shift;
    return "nmap";
}

sub command_regex {
    my $self = shift;
    return 'nmap\s.+?';
}

# Return 1 if OK.
# 0 if does not pass ACL.
# command_run will only be called if ACL passes.
sub acl_check {
    my ($self, %aclentry) = @_;

    my $permissions = $aclentry{'permissions'};
    my $who = $aclentry{'who'};
    my $channel = $aclentry{'channel'};
    my $message = $aclentry{'message'};

    # Available acl flags:
    # Hadouken::BIT_ADMIN
    # Hadouken::BIT_WHITELIST
    # Hadouken::BIT_OP 
    # Hadouken::VOICE
    # Hadouken::BIT_BLACKLIST

    # Make sure at least one of these flags is set.
    if($self->check_acl_bit($permissions, Hadouken::BIT_ADMIN) 
       || $self->check_acl_bit($permissions, Hadouken::BIT_WHITELIST)) {
        #|| $self->check_acl_bit($permissions, Hadouken::BIT_OP)) {

           return 1;
       }

    return 0;
}


sub command_run {
    my ($self,$nick,$host,$message,$channel,$is_admin,$is_whitelisted) = @_;
    my ($cmd, $arg) = split(/ /, lc($message),2);

    return unless (defined($arg) && length($arg));

    my ($hosts,$ports) = split(/ /,$arg, 2);

    return unless defined($hosts) && length($hosts); # && defined($ports) && length($ports));

    if(is_local_net($hosts)) {
        warn "* Trying to scan internal network";
        return 0;
    }

    #chomp($hosts);

    # Disable setting ports until we restrict.
    # $ports = undef;

    # Attempt to see if it's a nick we want to scan.
    my $con = $self->{Owner}{con};
    my $ident = $con->nick_ident($hosts);
    
    if(defined $ident && length $ident) {
        my (undef,$h) = split /@/, $ident;
        if(defined $h && length $h) {
            warn "* Nmap - scanning user $hosts on host $h";
            $hosts = $h;
        }
    }

    my $np = new Nmap::Parser;

    #$np->cache_scan('nmap.'.$hosts.'.xml');
    #$np->cache_scan('nmap.cache.xml');

    $np->callback( sub {
            my $host = shift;
            my $addr = $host->addr;

            if(is_local_net($addr)) {
                warn "* Trying to scan internal network (in callback)";

                $self->send_server (PRIVMSG => $channel, "no....");
                warn "* Trying to scan internal network (in callback)";
                return 0;
            }
            
            my $os   = $host->os_sig;
            my $host_status = String::IRC->new($host->status);

            $host_status->light_green if lc($host->status) eq 'up';
            $host_status->red if lc($host->status) eq 'down';

            my $pretty_status = $host->hostname . " (".$addr.") is ".$host_status;
            $self->send_server (PRIVMSG => $channel, $pretty_status);

            my @open = $host->tcp_ports('open'); # even 'open|filtered'

            foreach my $port (@open) {
                my $svc = $host->tcp_service($port)->name;
                my $state = $host->tcp_port_state($port);
                my $confidence = $host->tcp_service($port)->confidence;
                my $port_state_pretty = String::IRC->new($state);
                $port_state_pretty->light_green if lc($state) eq 'open';
                my $f_pretty = $host->hostname." (".$addr."), found ".$port_state_pretty." port "; #port ".join('/',$port->protocol(), $port->portid());

                if(defined $svc && length $svc) {
                    $f_pretty .= "$port($svc)";
                } else {
                    $f_pretty .= $port;
                }

                $self->send_server (PRIVMSG => $channel, $f_pretty);
            }

            if(defined $os->name && length $os->name && defined $os->name_accuracy && length $os->name_accuracy) {
                my $os_summary = $host->hostname." (".$addr.") - OS: ".$os->name." / (".$os->name_accuracy."\% probability)";
                $self->send_server (PRIVMSG => $channel, $os_summary);
            }

        });

    my $port_arg = defined $ports && length $ports ? '-p '.$ports : '-F --top-ports 100';
    $np->parsescan('/usr/bin/nmap','-Pn --dns-servers 8.8.8.8 -O -T4 -sS '.$port_arg, $hosts); # --dns-servers 8.8.8.8 

    return 1;
}

sub is_local_net {
    my $host = shift;
    if($host =~ m/(^localhost)|(^127\.0\.0\.1)|(^10\.)|(^172\.1[6-9]\.)|(^172\.2[0-9]\.)|(^172\.3[0-1]\.)|(^192\.168\.)/) {
        return 1;
    }

    return 0;
}


1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Hadouken::Plugin::Ticker - Crypto-currency ticker plugin.

=head1 DESCRIPTION

Crypto ticker plugin for Hadouken.

=head1 AUTHOR

dek - L<http://dek.codes/>

=cut

