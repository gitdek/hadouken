use strict;

use Test::More;                                 # tests => 8;                                 # qw(no_plan);
use ExtUtils::MakeMaker qw/prompt/;

use vars qw/$REMOTE_TESTS/;

diag("Performing AsyncSocket tests");

BEGIN {
    use_ok('Hadouken::AsyncSocket');
    use_ok('AnyEvent');

    require_ok('HTTP::Cookies');
} ## ---------- end BEGIN

$REMOTE_TESTS = 'y';

#$REMOTE_TESTS ||='y';

diag("Testing AsyncSocket $Hadouken::AsyncSocket::VERSION, Perl $], $^X");

# get_network_permission();

my $testurl = 'http://www.google.com';

my $asock = new_ok( 'Hadouken::AsyncSocket' => [ timeout => 30 ] );

$asock->timeout(15);

cmp_ok( $asock->timeout, '==', '15', 'timeout set' );

my $cv;                                         # = AE::cv;

SKIP: {
    skip "REMOTE TESTS", 2 unless $REMOTE_TESTS eq "y";
    diag("Performing network tests");

    $cv = AE::cv if $REMOTE_TESTS eq "y";

    # This doesnt count as a test.
    ok( test_network(), "began network test" );

    my ( $response, $header ) = $cv->recv if defined $cv;

    isnt( $response, undef, "Response" );
    isnt( $header,   undef, "Header" );
} ## ---------- end SKIP:

sub test_network {
    $asock->get(
        $testurl,
        sub {
            my ( $b, $h ) = @_;
            $cv->(@_);
        }
    );

    return 1;
} ## ---------- end sub test_network

sub get_network_permission {
    print <<EOB;

Would you like to test this module on a remote server?
It will be using http://google.com for testing.

EOB

    $REMOTE_TESTS = prompt( "Test with a network connection", "y" );

} ## ---------- end sub get_network_permission

done_testing();

