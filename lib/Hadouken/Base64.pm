package Hadouken::Base64;

use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK $VERSION);

require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw(encode_base64 decode_base64);
@EXPORT_OK
    = qw(encode_base64url decode_base64url encoded_base64_length decoded_base64_length);

$VERSION = '3.14';

require XSLoader;
XSLoader::load( 'Hadouken::Base64', $VERSION );

*encode = \&encode_base64;
*decode = \&decode_base64;

sub encode_base64url {
    my $e = encode_base64( shift, "" );
    $e =~ s/=+\z//;
    $e =~ tr[+/][-_];
    return $e;
} ## ---------- end sub encode_base64url

sub decode_base64url {
    my $s = shift;
    $s =~ tr[-_][+/];
    $s .= '=' while length($s) % 4;
    return decode_base64($s);
} ## ---------- end sub decode_base64url

1;

__END__

=head1 NAME

Hadouken::Base64 - Encoding and decoding of base64 strings

=head1 SYNOPSIS

 use Hadouken::Base64;

 $encoded = encode_base64('Aladdin:open sesame');
 $decoded = decode_base64($encoded);

=head1 DESCRIPTION

This module provides functions to encode and decode strings into and from the
base64 encoding specified in RFC 2045 - I<Hadouken (Multipurpose Internet
Mail Extensions)>. The base64 encoding is designed to represent
arbitrary sequences of octets in a form that need not be humanly
readable. A 65-character subset ([A-Za-z0-9+/=]) of US-ASCII is used,
enabling 6 bits to be represented per printable character.

The following primary functions are provided:

=over 4

=item encode_base64( $bytes )

=item encode_base64( $bytes, $eol );

Encode data by calling the encode_base64() function.  The first
argument is the byte string to encode.  The second argument is the
line-ending sequence to use.  It is optional and defaults to "\n".  The
returned encoded string is broken into lines of no more than 76
characters each and it will end with $eol unless it is empty.  Pass an
empty string as second argument if you do not want the encoded string
to be broken into lines.

The function will croak with "Wide character in subroutine entry" if $bytes
contains characters with code above 255.  The base64 encoding is only defined
for single-byte characters.  Use the Encode module to select the byte encoding
you want.

=item decode_base64( $str )

Decode a base64 string by calling the decode_base64() function.  This
function takes a single argument which is the string to decode and
returns the decoded data.

Any character not part of the 65-character base64 subset is
silently ignored.  Characters occurring after a '=' padding character
are never decoded.

=back

If you prefer not to import these routines into your namespace, you can
call them as:

    use Hadouken::Base64 ();
    $encoded = Hadouken::Base64::encode($decoded);
    $decoded = Hadouken::Base64::decode($encoded);

Additional functions not exported by default:

=over 4

=item encode_base64url( $bytes )

=item decode_base64url( $str )

Encode and decode according to the base64 scheme for "URL applications" [1].
This is a variant of the base64 encoding which does not use padding, does not
break the string into multiple lines and use the characters "-" and "_" instead
of "+" and "/" to avoid using reserved URL characters.

=item encoded_base64_length( $bytes )

=item encoded_base64_length( $bytes, $eol )

Returns the length that the encoded string would have without actually
encoding it.  This will return the same value as C<< length(encode_base64($bytes)) >>,
but should be more efficient.

=item decoded_base64_length( $str )

Returns the length that the decoded string would have without actually
decoding it.  This will return the same value as C<< length(decode_base64($str)) >>,
but should be more efficient.

=back

=head1 SEE ALSO

L<Hadouken>

[1] L<http://en.wikipedia.org/wiki/Base64#URL_applications>

=cut
