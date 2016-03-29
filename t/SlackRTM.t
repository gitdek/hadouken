use strict;

# use Test::More tests => 12;

use Data::Printer alias => 'Dumper', colored => 1;

use Test::More;

use AnyEvent;
use AnyEvent::SlackRTM;

$SIG{__DIE__} = sub { warn @_; die @_ };

# my $name = 'hadouken';
# my $webhook_url = 'https://hooks.slack.com/services/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';
my $token = $ENV{SLACK_TOKEN};

if ($token) {
    plan tests => 9;
}
else {
    plan skip_all => 'No SLACK_TOKEN configured for testing.';
}

my $rtm = AnyEvent::SlackRTM->new($token);
isa_ok( $rtm, 'AnyEvent::SlackRTM' );

my $c = AnyEvent->condvar;
$rtm->on(
    'hello' => sub {
        isa_ok( $_[0], 'AnyEvent::SlackRTM' );
        is( $_[1]{type}, 'hello', 'got hello' );
        ok( $rtm->said_hello, 'said hello' );

        $rtm->ping( { echo => 'I am your father!' } );
    }
);

$rtm->on(
    'pong' => sub {
        isa_ok( $_[0], 'AnyEvent::SlackRTM' );
        is( $_[1]{type}, 'pong', 'got pong' );
        is( $_[1]{echo}, 'I am your father!', 'echo message returned' );

        # $rtm->close;
    }
);

$rtm->on(
    'message' => sub {
        my ( $self, $message ) = (@_);

        is( $_[1]{type}, 'message', 'got message' );    # >'+ $_[1]{text});
                                                # is_deeply($got_complex_structure, $expected_complex_structure, 'test_name');
        diag(">> $_[1]{text}");

        #print Dumper($message);
        #	print Dumper($self);
    }
);

$rtm->on(
    'finish' => sub {
        isa_ok( $_[0], 'AnyEvent::SlackRTM' );
        ok( $rtm->finished, 'is finished' );
        $c->send;
    }
);

$rtm->start;
$c->recv;

