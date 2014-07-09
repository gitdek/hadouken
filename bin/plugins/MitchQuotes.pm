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

package Hadouken::Plugin::MitchQuotes;

use strict;
use warnings;

use TryCatch;

our $VERSION = '0.1';
our $AUTHOR = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return "Random Mitch Hedberg quote";
}

# Clean name of command.
sub command_name {
    return "mitch";
}

sub command_regex {
    return 'mitch$';
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
    #my $minimum_perms = (1 << 0) | (1 << 1) | (1 << 3);

    #my $acl_min = (1 << Hadouken::BIT_ADMIN) | (1 << Hadouken::BIT_WHITELIST) | (1 << Hadouken::NOT_RIP);

    #my $value = ($permissions & $minimum_perms);

    #warn $value;

    #if($value > 0) {
        # At least one of the items is set.
        #    return 1;
        #}

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

    try {
        my $line;
        open(FILE,'<'.$self->{Owner}->{ownerdir}.'/../data/mitch_quotes') or die $!;
        srand;
        rand($.) < 1 && ($line = $_) while <FILE>;
        close(FILE);    

        
        my $wrapped;
        ($wrapped = $line) =~ s/(.{0,300}(?:\s|$))/$1\n/g;
        
        warn $wrapped;

        my @lines = split(/\n/,$wrapped);

        my $cnt = 0;
        foreach my $l (@lines) {
            next unless defined $l && length $l;
            $cnt++;
            $self->send_server(PRIVMSG => $channel, $cnt > 1 ? $l : "Mitch Hedberg - $l");
        }
    }
    catch($e) {
        warn $e;
    }


    return 1;
}

1;

