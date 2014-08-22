#===============================================================================
#
#         FILE: StockTicker.pm
#
#  DESCRIPTION: Plugin for Hadouken which gets stock info by ticker symbol.
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: YOUR NAME (), 
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 04/26/2014 01:10:31 AM
#     REVISION: ---
#===============================================================================

package Hadouken::Plugin::StockTicker;

use strict;
use warnings;

use Finance::Quote;
use TryCatch;
use String::IRC;

our $VERSION = '0.2';
our $AUTHOR = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return "Look up stock by stock <symbol>";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "stockticker";
}

sub command_regex {

    return '(stock|\.)\s.+?';
}

# Return 1 if OK.
# 0 if does not pass ACL.
sub acl_check {
    my ($self, %aclentry) = @_;

    my $permissions = $aclentry{'permissions'};
    my $who = $aclentry{'who'};
    my $channel = $aclentry{'channel'};
    my $message = $aclentry{'message'};

    # Hadouken::BIT_ADMIN OR Hadouken::BIT_WHITELIST OR Hadouken::BIT_OP Hadouken::NOT_RIP
    my $minimum_perms = (1 << 0) | (1 << 1) | (1 << 3);

    #my $acl_min = (1 << Hadouken::BIT_ADMIN) | (1 << Hadouken::BIT_WHITELIST) | (1 << Hadouken::NOT_RIP);

    my $value = ($permissions & $minimum_perms);

    #warn $value;

    if($value > 0) {
        # At least one of the items is set.
        return 1;
    }

    # Or you can do it with the function Hadouken exports.
    # Make sure at least one of these flags is set.
    if($self->check_acl_bit($permissions, Hadouken::BIT_ADMIN) 
        || $self->check_acl_bit($permissions, Hadouken::BIT_WHITELIST) 
        || $self->check_acl_bit($permissions, Hadouken::BIT_OP)) {

        return 1;
    }

    return 0;
}


# Return 1 if OK (and then callback can be called)
# Return 0 and the callback will not be called.
sub command_run {
    my ($self,$nick,$host,$message,$channel,$is_admin,$is_whitelisted) = @_;
    my ($cmd, $arg) = split(/ /, lc($message),2);

    return unless defined $arg;

    try {
        $arg = uc($arg);
        my $q = Finance::Quote->new();
        $q->require_labels(qw/price date high low volume/);
        $q->failover(0);
        $q->timeout(10);

        my %data = $q->fetch('usa', $arg);
        
        if ($data{$arg, 'success'}) {
            my $summary = $arg." "."(".$data{$arg,'name'}.") ";
            my $net_change = $data{$arg,'net'};
            my $p_change = $data{$arg,'p_change'};
            my $day_range = $data{$arg,'day_range'};
            my $year_range = $data{$arg,'year_range'};
            
            
            # Make everything pretty.
            my $pretty_nchange = String::IRC->new($net_change);
            my $pretty_pchange = String::IRC->new($p_change."%");
            $pretty_nchange->light_green if($net_change =~ /^\+/);
            $pretty_nchange->red if($net_change =~ /^\-/);
            $pretty_pchange->light_green if($p_change =~ /^\+/);
            $pretty_pchange->red if($p_change =~ /^\-/);
            $day_range =~ s/\s+//g;
            $year_range =~ s/\s+//g;

            $summary .= "Last: ".$data{$arg,'last'}." ".$pretty_nchange." ".$pretty_pchange." (Vol: ".$data{$arg,'volume'}.") ";
            $summary .= "Daily Range: (".$day_range.") Yearly Range: (".$year_range.") ";
            #my $summary = $data{$arg, 'name'} ." Price: ". $data{$arg, 'price'} ." Volume: ".$data{$arg, 'volume'}." High: ".$data{$arg, 'high'}." Low: ".$data{$arg, 'low'};
            $self->send_server (PRIVMSG => $channel, $summary);
        } else {
            warn "Failure";
        }
    } 
    catch($e) {
        warn $e;
    }


    return 1;
}

1;

