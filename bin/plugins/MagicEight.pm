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

package Hadouken::Plugin::MagicEight;

use strict;
use warnings;

use Finance::Quote;
use TryCatch;

our $VERSION = '0.1';
our $AUTHOR = 'dek';

my %responses = (
    'Yes' => [
        'Yes!',
        'Definitely!',
        'Sure',
        'I think so',
        'Fuck yeah!',
        'Hell yeah!',
        'Most certainly',
        'For sure',
        'Abso-fucking-lutely',
        'In-fucking-deed!',
        'Fuck yes',
    ],
    'No' => [
        'Nope',
        'No way!',
        'Of course not you pleb!',
        'I think not',
        'Negative',
        'Not a chance!',
        'Good God no!',
        'Absolutely no chance!',
        "You're kidding, right?",
        'No fucking chance',
    ],
    'Maybe' => [
        'Hmm, perhaps',
        'I suppose',
        'I don\'t know about that',
        'Not sure',
        'Ask me later',
        'How should I know?',
        "Haven't a fucking clue",
    ],
);


# Description of this command.
sub command_comment {
    my $self = shift;

    return "Magic 8-Ball";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "8ball";
}

sub command_regex {

    return '8ball\s.+?';
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

    return 0; # Just let everyone use it :)
}


# Return 1 if OK (and then callback can be called)
# Return 0 and the callback will not be called.
sub command_run {
    my ($self,$nick,$host,$message,$channel,$is_admin,$is_whitelisted) = @_;
    my ($cmd, $arg) = split(/ /, lc($message),2);

    return unless defined $arg;

    # First, if we were asked to pick from some options:
    if (my($option_list) = $arg =~ /(?:choose|pick) \s+ (?:from\s+)? (.+)/x) {
        my @options = split /\s+or\s+/, $option_list;
        my $picked = $options[ rand @options ];
        
        $self->send_server(PRIVMSG => $channel, "8ball picked: $picked");
        return 1;
    }


    my $result;
    if ($arg =~ / (?: alcohol | beer | pub | home | friday ) /xi) {
        $result = 'Yes';
    } elsif ($arg =~ / (?: cpai?nel | windows | exchange | work ) /xi) {
        $result = 'No';
    } else {
        $result = (rand() < 0.3) ? 'Maybe' : (rand() < 0.5) ? 'Yes' : 'No';
    }
    if ($arg =~ / (?: suck | fail | shit | fucked ) /xi) {
        $result = { 'Yes' => 'No', 'No' => 'Yes' }->{$result} || $result;
    }

    my $response = $responses{$result}[rand @{ $responses{$result} }];

    warn $response;

    $self->send_server(PRIVMSG => $channel, "8ball: $response");

    return 1;
}


1;

