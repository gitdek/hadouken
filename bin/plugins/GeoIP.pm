package Hadouken::Plugin::GeoIP;

use strict;
use warnings;

use Hadouken ':acl_modes';

use TryCatch;
use Regexp::Common;
use AnyEvent::DNS;

our $VERSION = '0.1';
our $AUTHOR  = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return "Geo IP lookup. eg geoip <ip> or <uri>";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "geoip";
}

sub command_regex {
    my $self = shift;

    return 'geoip\s.+?';
}

# Return 1 if OK.
# 0 if does not pass ACL.
sub acl_check {
    my ( $self, %aclentry ) = @_;

    my $permissions = $aclentry{'permissions'};

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
    my ( $self, $nick, $host, $message, $channel, $is_admin, $is_whitelisted )
        = @_;

    my ( $cmd, $arg ) = split( / /, $message, 2 );    # DO NOT LC THE MESSAGE!

    return unless defined $arg;
    if ( $arg =~ /$RE{net}{IPv4}/ ) {

        my $record = $self->{Owner}->{geoip}->record_by_addr($arg);

        return unless defined $record;

        my $ip_result = "$arg -> ";
        $ip_result .= " City:" . $record->city
            if defined $record->city && $record->city ne '';
        $ip_result .= " Region:" . $record->region
            if defined $record->region && $record->region ne '';
        $ip_result .= " Country:" . $record->country_code
            if defined $record->country_code && $record->country_code ne '';

        $self->send_server( PRIVMSG => $channel, $ip_result );

    }
    elsif ( $arg =~ m{($RE{URI})}gos ) {

        my $uri       = URI->new($arg);
        my $host_only = $uri->host;

        AnyEvent::DNS::resolver->resolve(
            $host_only,
            "a",
            sub {

                # array = "banana.com", "a", "in", 3290, "113.10.144.102"
                my $row = List::MoreUtils::last_value {
                    grep { $_ eq "a" } @$_
                }
                @_;

                return
                    unless ( defined $row )
                    || ( @$row[4] =~ /$RE{net}{IPv4}/ );

                my $ip_addr = @$row[4];

                return unless ( $ip_addr =~ /$RE{net}{IPv4}/ );

                my $record
                    = $self->{Owner}->{geoip}->record_by_addr($ip_addr);

                unless ( defined $record ) {
                    $self->send_server(
                        PRIVMSG => $channel,
                        "$arg ($ip_addr) -> no results in db"
                    );
                    return;
                }

                my $dom_result = "$arg ($ip_addr) ->";
                $dom_result .= " City:" . $record->city
                    if defined $record->city && $record->city ne '';
                $dom_result .= " Region:" . $record->region
                    if defined $record->region && $record->region ne '';
                $dom_result .= " Country:" . $record->country_code
                    if defined $record->country_code
                    && $record->country_code ne '';

                $self->send_server( PRIVMSG => $channel, $dom_result );
            }
        );
    }
    else {
        #        try {
        #            warn "Trying Other..\n";
        #
        #            #my $uri = URI->new($arg,'http');
        #            #my $host_only = $uri->host;
        #            AnyEvent::DNS::resolver->resolve ($arg, "a", sub {
        #
        #                    my $row = List::MoreUtils::last_value { grep { $_ eq "a" } @$_  } @_;
        #
        #                    return unless (defined $row) || (@$row[4] =~ /$RE{net}{IPv4}/);
        #
        #                    my $ip_addr = @$row[4];
        #
        #                    return unless ($ip_addr =~ /$RE{net}{IPv4}/);
        #
        #                    my $record = $self->{Owner}->{geoip}->record_by_addr($ip_addr);
        #
        #                    unless(defined $record) {
        #                        $self->send_server (PRIVMSG => $channel, "$arg ($ip_addr) -> no results in db");
        #                        return;
        #                    }
        #
        #                    my $dom_result = "$arg ($ip_addr) ->";
        #                    $dom_result .= " City:".$record->city if defined $record->city && $record->city ne '';
        #                    $dom_result .= " Region:".$record->region if defined $record->region && $record->region ne '';
        #                    $dom_result .= " Country:".$record->country_code if defined $record->country_code && $record->country_code ne '';
        #
        #                    $self->send_server (PRIVMSG => $channel, $dom_result);
        #                });
        #        }
        #        catch($e) {
        #            warn "* GeoIP failled for $e\n";
        #        }
        #
        #        return 1;

    }

    return 1;
} ## ---------- end sub command_run

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Hadouken::Plugin::GeoIP - GeoIP Lookup plugin.

=head1 DESCRIPTION

Perform GeoIP lookup queries.

=head1 AUTHOR

dek - L<http://dek.codes/>

=cut

