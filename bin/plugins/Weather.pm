package Hadouken::Plugin::Weather;

use strict;
use warnings;

use Hadouken ':acl_modes';
use utf8;
use TryCatch;
use Encode qw( encode );
use URI;

our $VERSION = '0.4';
our $AUTHOR  = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return
        "Get weather info by weather <zip> or <location>. command alias: w. add -c for celsius";
} ## ---------- end sub command_comment

# Clean name of command.
sub command_name {
    my $self = shift;

    return "weather";
}

sub command_regex {
    my $self = shift;

    return '(weather|forecast|w)\s.+?';

    #return 'weather\s.+?';
} ## ---------- end sub command_regex

# Return 1 if OK.
# 0 if does not pass ACL.
sub acl_check {
    my ( $self, %aclentry ) = @_;

    my $permissions = $aclentry{'permissions'};

    #    if($self->check_acl_bit($permissions, Hadouken::BIT_ADMIN)
    #        || $self->check_acl_bit($permissions, Hadouken::BIT_WHITELIST)
    #        || $self->check_acl_bit($permissions, Hadouken::BIT_OP)) {
    #
    #        return 1;
    #    }

    if ( $self->check_acl_bit( $permissions, Hadouken::BIT_BLACKLIST ) ) {
        return 0;
    }

    return 1;
} ## ---------- end sub acl_check

# Return 1 if OK (and then callback can be called)
# Return 0 and the callback will not be called.
sub command_run {
    my ( $self, $nick, $host, $message, $channel, $is_admin, $is_whitelisted ) = @_;

    my ( $cmd, $arg ) = split( / /, $message, 2 );    # DO NOT LC THE MESSAGE!

    return unless defined $arg;

    my $do_celsius = 0;

    if ( $arg =~ m/--?c/ ) {
        $do_celsius = 1;
        $arg =~ s/--?c//;
    }

    my $url = URI->new("https://wttr.in/$arg?0AFT");

    try {
        $self->asyncsock->get(
            $url,
            sub {
                my ( $body, $header ) = @_;
                return unless defined $body;

                if ( defined $body && $body ne '' ) {
                    for my $line ( split /\n/, $body ) {
                        next unless defined $line && $line ne '';
                        $self->send_server( PRIVMSG => $channel, encode( "utf8", $line ) );
                    }
                }
            }
        );
    }
    catch ($e) {
        warn("An error occured while weather was executing: $e");
    }

    return 1;
} ## ---------- end sub command_run

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Hadouken::Plugin::Weather - Weather plugin.

=head1 DESCRIPTION

Weather forecast plugin for Hadouken.

=head1 AUTHOR

dek <dek@whilefalsedo.com>

=cut

