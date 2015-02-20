package Hadouken::Plugin::ExamplePlugin;

use strict;
use warnings;

use Hadouken ':acl_modes';

our $VERSION = '0.1';
our $AUTHOR  = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return "This plugin is just an example.";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "Example Plugin";
}

sub command_regex {
    my $self = shift;

    #return 'exampleplugin\s.+?' # if you want some arguments...
    return 'exampleplugin$';
} ## ---------- end sub command_regex

# Return 1 if OK.
# 0 if does not pass ACL.
sub acl_check {
    my ( $self, %aclentry ) = @_;

    my $permissions = $aclentry{'permissions'};
    my $who         = $aclentry{'who'};
    my $channel     = $aclentry{'channel'};
    my $message     = $aclentry{'message'};

    # Available flags:
    # Hadouken::BIT_ADMIN
    # Hadouken::BIT_WHITELIST
    # Hadouken::BIT_BLACKLIST
    # Hadouken::BIT_OP
    # Hadouken::BIT_VOICE
    #

    if (   $self->check_acl_bit( $permissions, Hadouken::BIT_ADMIN )
        || $self->check_acl_bit( $permissions, Hadouken::BIT_WHITELIST )
        || $self->check_acl_bit( $permissions, Hadouken::BIT_OP ) )
    {

        return 1;
    }

    return 0;
} ## ---------- end sub acl_check

# Return 1 if OK (and then callback can be called)
# Return 0 and the callback will not be called.
sub command_run {
    my ( $self, $nick, $host, $message, $channel, $is_admin, $is_whitelisted ) = @_;

    # You can call send_server. The symbol table was rewritten.
    #$self->send_server(PRIVMSG => '#thechannel', "plugin doing something weee");

    return 1;
} ## ---------- end sub command_run

1;
