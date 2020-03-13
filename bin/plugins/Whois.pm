package Hadouken::Plugin::Whois;

use strict;
use warnings;

use Hadouken ':acl_modes';
use AnyEvent::DNS;
use AnyEvent::Whois::Raw;

#use Data::Printer alias => 'Dumper', colored => 1;

use TryCatch;

our $VERSION = '0.1';
our $AUTHOR  = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return "whois lookup";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "whois";
}

sub command_regex {
    my $self = shift;

    return 'whois\s.+?';
}

# Return 1 if OK.
# 0 if does not pass ACL.
sub acl_check {
    my ( $self, %aclentry ) = @_;

    my $permissions = $aclentry{'permissions'};

    #my $who = $aclentry{'who'};
    #my $channel = $aclentry{'channel'};
    #my $message = $aclentry{'message'};

    # Or you can do it with the function Hadouken exports.
    # Make sure at least one of these flags is set.
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
    my ( $cmd, $arg ) = split( / /, lc($message), 2 );

    return unless ( defined($arg) && length($arg) );

    AnyEvent::DNS::resolver->resolve(
        $arg, "a",
        accept => [ "a", "aaaa" ],
        sub {
            foreach my $rec (@_) {
                my ( undef, undef, undef, undef, $ip ) = @$rec;

                next unless ( defined $ip && length $ip );

                AnyEvent::Whois::Raw::get_whois $ip,
                    timeout => 10,
                    sub {
                    my $data = shift;
                    my %parsed;
                    if ($data) {
                        my $srv = shift;

                        for my $line ( split /\n/, $data ) {
                            chomp $line;
                            $line =~ s/^\s+//;
                            $line =~ s/\s+$//;

                            my ( $key, $value ) = $line =~ /^\s*([\d\w\s_-]+):\s*(.+)$/;
                            next if !$line || !$value;
                            $key   =~ s/\s+$//;
                            $value =~ s/\s+$//;

                            $parsed{$key} =
                                ref $parsed{$key} eq 'ARRAY'
                                ? [ @{ $parsed{$key} }, $value ]
                                : [$value];

                        }

                        my $sum = '[whois] ';
                        for my $key ( keys %parsed ) {
                            $sum .= $key . ":" . $parsed{$key}[0] . " ";
                        }

                        $self->send_server( PRIVMSG => $channel, $sum );
                    }
                    elsif ( !defined $data ) {
                        my $srv = shift;
                        warn "* WHOIS No whois data information for domain on $srv found";
                    }
                    else {
                        my $reason = shift;
                        warn "* WHOIS error: $reason";
                    }
                    };

                last;
            }

        }
    );

    return 1;
} ## ---------- end sub command_run

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Hadouken::Plugin::Whois - Whois plugin.

=head1 DESCRIPTION

Whois plugin for Hadouken.

=head1 AUTHOR

dek <dek@whilefalsedo.com>

=cut

