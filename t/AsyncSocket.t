#!/usr/bin/env perl

use strict;
use warnings;

BEGIN { eval "use blib" }
use v5.14;

use Test::More;
use ExtUtils::MakeMaker qw/prompt/;

use vars qw/$REMOTE_TESTS/;

BEGIN {
    use_ok('Hadouken::AsyncSocket');
    use_ok('AnyEvent');

    require_ok('HTTP::Cookies');
} ## ---------- end BEGIN

#get_network_permission();

$REMOTE_TESTS = 'y';

#$REMOTE_TESTS ||='';

diag("Testing Hadouken::AsyncSocket $Hadouken::AsyncSocket::VERSION, Perl $], $^X");

my $testurl = 'http://www.google.com';

my $asock = new_ok( 'Hadouken::AsyncSocket' => [ timeout => 30 , debug => 1, hexdump => 1] );

$asock->timeout(60);

cmp_ok( $asock->timeout, '==', '60', 'timeout set' );

my $cv;                                         # = AE::cv;

SKIP: {
    skip "REMOTE TESTS", 2 unless $REMOTE_TESTS eq "y";
    diag("Performing network tests");

    $cv = AE::cv if $REMOTE_TESTS eq "y";

    # This doesnt count as a test.
    #ok( test_api(), "began network test" );
    ok( test_weather(), "began network test" );

    my ( $response, $header ) = $cv->recv;

    warn "response length: ". length($response);
    warn $response;

    #isnt( $response, undef, "Response" );
    #isnt( $header,   undef, "Header" );
} ## ---------- end SKIP:


sub test_api {

    my $api_url = "https://apidojo-yahoo-finance-v1.p.rapidapi.com/stock/get-detail?region=US&lang=en&symbol=TSLA";

    my $lwp = LWP::UserAgent->new(
        keep_alive => 1,
        agent => 'Test 1.0',
        timeout => 60,
        ssl_opts => { verify_hostname => 0 },
        requests_redirectable => ['GET', 'HEAD', 'POST']
    );

    my $req = HTTP::Request->new (
        GET => $api_url
    );

    #my %hdr;
    ##$hdr{"x-rapidapi-host"} = 'apidojo-yahoo-finance-v1.p.rapidapi.com';
    #$hdr{"x-rapidapi-key"} = '4f98308d8dmshb2bc4d493bc9df9p1cd5b4jsn896a8e19d288';

    $req->header("x-rapidapi-host" => 'apidojo-yahoo-finance-v1.p.rapidapi.com');
    $req->header('x-rapidapi-key' => '4f98308d8dmshb2bc4d493bc9df9p1cd5b4jsn896a8e19d288');

    #my $resp = $lwp->request($req);
    #my $reply = $resp->content;
    #print $resp->as_string;


    #$self->hexdump("Incoming:", $resp->as_string);
    $asock->request2($req,
       sub {
           my ( $b, $h ) = @_;

           warn "Entered callback.\n";

           #warn $b;
           #warn $h;
           $cv->(@_);
       }
    );

    return 1;
}


sub test_weather {

    $asock->get(
        "https://wttr.in/33442?0ATq",
        sub {
            my ( $b, $h ) = @_;
            $cv->(@_);
        }
    );

    return 1;

}


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

