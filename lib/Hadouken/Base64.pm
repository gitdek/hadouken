package Hadouken::Base64;

use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK $VERSION);

require Exporter;
@ISA       = qw(Exporter);
@EXPORT    = qw(encode_base64 decode_base64);
@EXPORT_OK = qw(encode_base64url decode_base64url encoded_base64_length decoded_base64_length);

$VERSION = '0.2';

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