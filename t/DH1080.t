use strict;

# use Test::More qw(no_plan);
use Test::More tests => 3;

BEGIN { use_ok('Hadouken::DH1080') };

diag( "Testing Hadouken::DH1080, Perl $], $^X" );

my $msg = 'hello how are you';

my $enc = Hadouken::DH1080->encodeB64($msg);
my $dec = Hadouken::DH1080->decodeB64($enc);

# print "$msg\n$dec\n";
ok ( $msg eq $dec );

# test message exchange
my $alice = Hadouken::DH1080->new();
my $bob = Hadouken::DH1080->new();

my $alice_init = $alice->public_key;
my $bob_secret = $bob->get_shared_secret($alice_init);
my $bob_finish = $bob->public_key;
my $alice_secret = $alice->get_shared_secret($bob_finish);
ok ( $bob_secret eq $alice_secret );

