package Hadouken::DH1080;
use strict;
use warnings;

use Crypt::Random qw(makerandom);
use Math::BigInt try => 'GMP';
use Digest::SHA;

require Exporter;

our @ISA         = qw(Exporter);
our %EXPORT_TAGS = (
    'all' => [
        qw(
            )
    ]
);

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw();

our $VERSION = '0.1';

my $B64_DH1080 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

my $P =
    Math::BigInt->from_hex( '0x'
        . 'FBE1022E23D213E8ACFA9AE8B9DFAD'
        . 'A3EA6B7AC7A7B7E95AB5EB2DF85892'
        . '1FEADE95E6AC7BE7DE6ADBAB8A783E'
        . '7AF7A7FA6A2B7BEB1E72EAE2B72F9F'
        . 'A2BFB2A2EFBEFAC868BADB3E828FA8'
        . 'BADFADA3E4CC1BE7E8AFE85E9698A7'
        . '83EB68FA07A77AB6AD7BEB618ACF9C'
        . 'A2897EB28A6189EFA07AB99A8A7FA9'
        . 'AE299EFA7BA66DEAFEFBEFBF0B7D8B' );

sub new {
    my ($class) = @_;

    my $g = Math::BigInt->new(2);
    my $p = $P;
    my $q = $p->copy()->bsub(1)->bdiv(2);

    my $private = Math::BigInt->new( makerandom( Size => 1080 ) );
    my $public  = $g->copy()->bmodpow( $private, $p );

    my $self = {
        _private_key => $private,
        _public_key  => $public,
        _q           => $q,
        _p           => $p,
        _g           => $g
    };

    return bless $self, $class;
} ## ---------- end sub new

sub as_string {
    my ($self) = @_;

    return sprintf(
        "Hadouken::DH1080 public_key=%s, private_key=%s",
        $self->{_public_key}->bstr(),
        $self->{_private_key}->bstr()
    );
} ## ---------- end sub as_string

sub public_key {
    my ($self) = @_;
    return Hadouken::DH1080->encodeB64( Hadouken::DH1080->int2bytes( $self->{_public_key} ) );
}

sub get_shared_secret {
    my ( $self, $peer_pub_key ) = @_;

    my $public = Hadouken::DH1080->bytes2int( Hadouken::DH1080->decodeB64($peer_pub_key) );
    if ( $public->bcmp(1) <= 0 || $public->bcmp( $self->{_p} ) >= 0 ) {
        warn sprintf( "Public key outside range: %s", $public->bstr() );
        return undef;
    }

    my $secret = $public->bmodpow( $self->{_private_key}, $self->{_p} );
    my $digest = Digest::SHA->new(256);
    $digest->add( Hadouken::DH1080->int2bytes($secret) );
    return Hadouken::DH1080->encodeB64( $digest->digest );
} ## ---------- end sub get_shared_secret

sub bytes2int {
    my ( $class, $a ) = @_;
    my @b = split //, $a;
    my $n = Math::BigInt->new(0);

    foreach my $p (@b) {
        $n->bmul(256);
        $n->badd( ord($p) );
    }
    return $n;
} ## ---------- end sub bytes2int

sub int2bytes {
    my ( $class, $n ) = @_;
    my $t = $n->copy();
    if ( $t->is_zero() ) {
        return "";
    }

    my $b = '';
    while ( $t->bcmp(0) > 0 ) {
        $b = chr( $t->copy()->bmod(256)->as_int() ) . $b;
        $t->bdiv(256);
    }
    return $b;
} ## ---------- end sub int2bytes

sub encodeB64 {
    my ( $class, $text ) = @_;

    my @s   = split //, $text;
    my @b64 = split //, $B64_DH1080;
    my @d   = ();
    my $L   = scalar(@s) * 8;
    my $m   = 0x80;
    my $i   = 0;
    my $j   = 0;
    my $k   = 0;
    my $t   = 0;

    while ( $i < $L ) {
        $t |= 1 if ord( $s[ $i >> 3 ] ) & $m;
        $j += 1;
        $m >>= 1;
        if ( !$m ) {
            $m = 0x80;
        }
        if ( $j % 6 == 0 ) {
            $d[$k] = $b64[$t];
            $t &= 0;
            $k += 1;
        }
        $t <<= 1;
        $t %= 0x100;
        #
        $i += 1;
    }
    $m = 5 - $j % 6;
    $t <<= $m;
    $t %= 0x100;
    if ($m) {
        $d[$k] = $b64[$t];
        $k += 1;
    }
    $d[$k] = '';
    my $res = '';
    foreach my $q (@d) {
        last if $q eq '';
        $res .= $q;
    }
    return $res;
} ## ---------- end sub encodeB64

sub decodeB64 {
    my ( $class, $text ) = @_;
    my @s   = split //, $text;
    my @b64 = split //, $B64_DH1080;
    my @buf = ();

    for my $i ( 0 .. 63 ) {
        $buf[ ord( $b64[$i] ) ] = $i;
    }

    my $L = scalar(@s);

    return undef if $L < 2;

    foreach my $i ( reverse( 0 .. $L - 1 ) ) {
        if ( $buf[ ord( $s[$i] ) ] == 0 ) {
            $L -= 1;
        }
        else {
            last;
        }
    }

    return undef if $L < 2;

    my @d = ();

    # d = [0]*L

    my $i = 0;
    my $k = 0;

    while (1) {
        $i += 1;

        if ( $k + 1 < $L ) {
            $d[ $i - 1 ] = $buf[ ord( $s[$k] ) ] << 2;
            $d[ $i - 1 ] %= 0x100;
        }
        else {
            last;
        }
        $k += 1;
        if ( $k < $L ) {
            $d[ $i - 1 ] |= $buf[ ord( $s[$k] ) ] >> 4;
        }
        else {
            last;
        }

        $i += 1;
        if ( $k + 1 < $L ) {
            $d[ $i - 1 ] = $buf[ ord( $s[$k] ) ] << 4;
            $d[ $i - 1 ] %= 0x100;
        }
        else {
            last;
        }

        $k += 1;
        if ( $k < $L ) {
            $d[ $i - 1 ] |= $buf[ ord( $s[$k] ) ] >> 2;
        }
        else {
            last;
        }

        $i += 1;
        if ( $k + 1 < $L ) {
            $d[ $i - 1 ] = $buf[ ord( $s[$k] ) ] << 6;
            $d[ $i - 1 ] %= 0x100;
        }
        else {
            last;
        }
        $k += 1;
        if ( $k < $L ) {
            $d[ $i - 1 ] |= $buf[ ord( $s[$k] ) ] % 0x100;
        }
        else {
            last;
        }
        $k += 1;
    }
    return join( "", map( chr, splice( @d, 0, $i - 1 ) ) );
} ## ---------- end sub decodeB64

sub to_hex {
    my ( $class, $binary ) = @_;
    return '0x' . unpack( "H*", $binary );
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Hadouken::DH1080 - DH1080 key exchange.

=head1 DESCRIPTION

DH1080 key exchange.

=head1 AUTHOR

dek - L<http://dek.codes/>

=cut

=head1 SEE ALSO

L<Hadouken>

[1] L<http://en.wikipedia.org/wiki/Diffie%E2%80%93Hellman_key_exchange>

=cut


