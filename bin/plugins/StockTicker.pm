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

our $VERSION = '0.2';
our $AUTHOR = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return "StockTicker Plugin weee";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "StockTicker Plugin";
}

sub command_regex {
    my $self = shift;

    return 'wee$';
}

# Return 1 if OK.
# 0 if does not pass ACL.
sub acl_check {
    my ($self,$nick,$host,$message,$channel,$is_admin,$is_whitelisted) = @_;

    warn "$nick $host $message $channel, is_admin:$is_admin, is_whitelisted:$is_whitelisted\n";

    return 1;
}

# Return 1 if OK (and then callback can be called)
# Return 0 and the callback will not be called.
sub command_run {
    my ($self,$nick,$host,$message,$channel,$is_admin,$is_whitelisted) = @_;

    # You can call send_server, we rewrote symbol table.
    $self->send_server(PRIVMSG => '#hadouken', "plugin doing something weee");

    return 1;
}

1;

