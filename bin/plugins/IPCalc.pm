package Hadouken::Plugin::IPCalc;

use strict;
use warnings;

use Hadouken ':acl_modes';
use TryCatch;
use Data::Dumper;
use Regexp::Common;

our $VERSION = '0.1';
our $AUTHOR  = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return
      "Calculate IP netmask or CIDR. eg ipcalc 192.168.0.1/24 or ipcalc 192.168.0.1/255.255.255.0";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "ipcalc";
}

sub command_regex {
    my $self = shift;

    return 'ipcalc\s.+?';
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
}

# Return 1 if OK (and then callback can be called)
# Return 0 and the callback will not be called.
sub command_run {
    my ( $self, $nick, $host, $message, $channel, $is_admin, $is_whitelisted ) = @_;

    my ( $cmd, $arg ) = split( / /, $message, 2 ); # DO NOT LC THE MESSAGE!

    return unless defined $arg;

    my ( $network, $netbit ) = split( /\//, $arg );

    return
         unless ( defined($network) )
      && ( defined($netbit) )
      && ( $network =~ /$RE{net}{IPv4}/ );

    if (   ( $netbit =~ /^$RE{num}{int}$/ )
        && ( $netbit <= 32 )
        && ( $netbit >= 0 ) )
    {

        my $res_calc = $self->calc_netmask( $network . "\/" . $netbit );

        my $res_usable = $self->cidr2usable_v4($netbit);

        return unless ( defined $res_calc ) || ( defined $res_usable );

        my $out_msg = "[ipcalc] $arg -> netmask: $res_calc - usable addresses: $res_usable";

        $self->send_server( PRIVMSG => $channel, $out_msg );
    }
    elsif ( $netbit =~ /$RE{net}{IPv4}/ ) {

        my $cidr = $self->netmask2cidr( $netbit, $network );

        my $poop = "[ipcalc] $arg -> cidr $cidr";

        $self->send_server( PRIVMSG => $channel, $poop );
    }

    return 1;

}

sub calc_netmask {
    my ( $self, $subnet ) = @_;

    my ( $network, $netbit ) = split( /\//, $subnet );

    my $bit = ( 2**( 32 - $netbit ) ) - 1;

    my ($full_mask) = unpack( "N", pack( 'C4', split( /\./, '255.255.255.255' ) ) );

    return join( '.', unpack( 'C4', pack( "N", ( $full_mask ^ $bit ) ) ) );
}

sub netmask2cidr {
    my ( $self, $mask, $network ) = @_;
    my @octet = split( /\./, $mask );
    my @bits;
    my $binmask;
    my $binoct;
    my $bitcount = 0;

    foreach (@octet) {
        $binoct = unpack( "B32", pack( "N", $_ ) );
        $binmask = $binmask . substr $binoct, -8;
    }

    @bits = split( //, $binmask );
    foreach (@bits) {
        $bitcount++ if ( $_ eq "1" );
    }

    my $cidr = $network . "/" . $bitcount;
    return $cidr;
}

sub cidr2usable_v4 {
    my ( $self, $bit ) = @_;

    return ( 2**( 32 - $bit ) );
    # return 1 << ( 32-$bit ); works but its fucking up my IDE lol
}

1;

