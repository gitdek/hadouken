#!/usr/bin/env perl

use strict;
use warnings;

use v5.14;

use Test::More;

BEGIN { 
	use_ok('Hadouken::DH1080');
}

diag("Testing Hadouken::DH1080 $Hadouken::DH1080::VERSION, Perl $], $^X");

my $msg = 'hello how are you';

my $enc = Hadouken::DH1080->encodeB64($msg);
isnt( $enc, undef, "enc" );

my $dec = Hadouken::DH1080->decodeB64($enc);
isnt( $dec, undef, "dec" );


cmp_ok( $dec, 'eq', $msg, 'compare decoded b64 to original message' );

# test message exchange

my $alice = new_ok( 'Hadouken::DH1080' );
my $bob = new_ok( 'Hadouken::DH1080' );

my $alice_init   = $alice->public_key;
isnt( $alice_init, undef, "alice_init" );

my $bob_secret   = $bob->get_shared_secret($alice_init);
isnt( $bob_secret, undef, "bob_secret" );

my $bob_finish   = $bob->public_key;
isnt( $bob_finish, undef, "bob_finish" );

my $alice_secret = $alice->get_shared_secret($bob_finish);
isnt( $alice_secret, undef, "alice_secret" );

cmp_ok( $bob_secret, 'eq', $alice_secret, 'secrets compare' );

done_testing();