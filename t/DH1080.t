#!/usr/bin/env perl

use strict;
use warnings;

use v5.14;

use Test::More;

BEGIN {
    use_ok('Hadouken::DH1080');
    use_ok('Hadouken::Base64');
}

diag("Testing Hadouken::DH1080 $Hadouken::DH1080::VERSION, Perl $], $^X");

my $dh = Hadouken::DH1080->new();

my $msg = 'hello how are you';

my $enc = $dh->encodeB64($msg);

#cmp_ok( $enc, 'eq', $enc2, 'base64 encodings match' );

isnt( $enc, undef, "enc" );

my $dec = decode_base64($enc);
isnt( $dec, undef, "dec" );

if ( exists $ENV{'LAZY_DH1080'} ) {
    diag("Skipping comparison test");
}
else {
    cmp_ok( $dec, 'eq', $msg, 'compare decoded b64 to original message' );
}

# test message exchange

my $alice = new_ok('Hadouken::DH1080');
my $bob   = new_ok('Hadouken::DH1080');

my $alice_init = $alice->public_key();
isnt( $alice_init, undef, "alice_init" );

my $bob_secret = $bob->get_shared_secret($alice_init);
isnt( $bob_secret, undef, "bob_secret" );

my $bob_finish = $bob->public_key();
isnt( $bob_finish, undef, "bob_finish" );

my $alice_secret = $alice->get_shared_secret($bob_finish);
isnt( $alice_secret, undef, "alice_secret" );

cmp_ok( $bob_secret, 'eq', $alice_secret, 'secrets compare' );

done_testing();
