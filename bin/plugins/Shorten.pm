package Hadouken::Plugin::Shorten;

use strict;
use warnings;

use Hadouken ':acl_modes';

use TryCatch;
use Data::Dumper;
use Regexp::Common;
use AnyEvent::DNS;

our $VERSION = '0.2';
our $AUTHOR  = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return "Shorten URL";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "shorten";
}

sub command_regex {
    my $self = shift;

    return 'shorten\s.+?';
}

# Return 1 if OK.
# 0 if does not pass ACL.
sub acl_check {
    my ( $self, %aclentry ) = @_;

    my $permissions = $aclentry{'permissions'};

    if ( $self->check_acl_bit( $permissions, Hadouken::BIT_BLACKLIST ) ) {
        return 0;
    }
    
    #if (   $self->check_acl_bit( $permissions, Hadouken::BIT_ADMIN )
    #    || $self->check_acl_bit( $permissions, Hadouken::BIT_WHITELIST )
    #    || $self->check_acl_bit( $permissions, Hadouken::BIT_OP ) )
    #{
    #
    #    return 1;
    #}

    return 1;
} ## ---------- end sub acl_check

# Return 1 if OK (and then callback can be called)
# Return 0 and the callback will not be called.
sub command_run {
    my ( $self, $nick, $host, $message, $channel, $is_admin, $is_whitelisted ) = @_;

    my ( $cmd, $arg ) = split( / /, $message, 2 );    # DO NOT LC THE MESSAGE!

    return unless defined $arg;

    my ($uri) = $arg =~ /$RE{URI}{HTTP}{-scheme=>'https?'}{-keep}/;

    return 0 unless defined $uri;

    # Only grab title for admins.
    my ( $url, $title ) =
        $self->{Owner}->_shorten( $uri, 1 );    # $self->{Owner}->is_admin($who));

    if ( defined $url && $url ne '' ) {
        if ( defined $title && $title ne '' ) {
            $self->send_server( PRIVMSG => $channel, "$url ($title)" );
        }
        else {
            $self->send_server( PRIVMSG => $channel, "$url" );
        }
    }

    return 1;
} ## ---------- end sub command_run

1;

