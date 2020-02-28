package Hadouken::AsyncSocket;

use strict;
use warnings;
use utf8;

use Errno;
use AnyEvent;
use AnyEvent::HTTP;
use AnyEvent::HTTP::Request;
use AnyEvent::HTTP::Response;
use AnyEvent::Util;
use AnyEvent::Socket;
use AnyEvent::Handle;
use HTTP::Request::Common ();
use HTTP::Request;
use HTTP::Response;
use HTTP::Cookies;

use Time::HiRes qw(time);
use LWP::UserAgent;
use Log::Log4perl qw( get_logger );
use Encode;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;


our $VERSION = '0.02';


subtype 'Hadouken::AsyncSocket::Cookies' => as class_type('HTTP::Cookies');
coerce 'Hadouken::AsyncSocket::Cookies' => from 'HashRef' => via { HTTP::Cookies->new( %{$_} ) };

# This will handle asynchronous DNS, HTTP and other sockets.

has timeout => ( is => 'rw', isa => 'Int', default => sub { 30 } );
has agent   => (
    is      => 'rw',
    isa     => 'Str',
    default => sub { 'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1)' }
);                                              #join "/", __PACKAGE__, $VERSION });

has cookies => (is => 'rw', isa => 'Hadouken::AsyncSocket::Cookies', coerce => 1, default => sub { HTTP::Cookies->new });
has proxypac =>     ( is => 'rw', isa => 'Str', required => 0 );
has proxyhost =>    ( is => 'rw', isa => 'Str', required => 0 );
has proxyport =>    ( is  => 'rw', isa => subtype( 'Int' => where { $_ > 0} ), required => 0 );
has proxytype =>    ( is => 'rw', isa => enum([ qw(none https socks pac) ]), default => 'none' );
has useragent =>    ( is => 'rw', isa => 'Str', required => 0 );

sub BUILD {
    my $self = shift;
    my $args = shift;

    $self->{debug} = $args->{debug} || 0;
    $self->{slave} = $args->{slave} || undef;
    $self->{hexdump} = $args->{hexdump} || 0;

    $self->{sock} = undef;
    $self->{socket} = undef;
    # Global handlers to be propagated to all sub-classes.
    $self->{handlers} => {};

    $self->{cv} = AnyEvent->condvar( cb => sub { warn "done WTF"; });;
    $self->{cbresult} = undef;


    $self->{socket} = LWP::UserAgent->new(
        keep_alive => 1,
        agent => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:73.0) Gecko/20100101 Firefox/73.0',
        timeout => 60,
        ssl_opts => { verify_hostname => 0 },
        requests_redirectable => ['GET', 'HEAD', 'POST']
    );

}

sub get    { _request( GET    => @_ ) }
sub head   { _request( HEAD   => @_ ) }
sub post   { _request( POST   => @_ ) }
sub put    { _request( PUT    => @_ ) }
sub delete { _request( DELETE => @_ ) }

sub _request {
    my $cb     = pop;
    my $method = shift;
    my $self   = shift;
    no strict 'refs';
    my $req = &{"HTTP::Request::Common::$method"}(@_);
    $self->request( $req, $cb );
} ## ---------- end sub _request

sub request {
    my ( $self, $request, $cb ) = @_;

    $request->headers->user_agent( $self->agent );
    $self->cookies->add_cookie_header($request);

    my %options = (
        timeout => $self->timeout,
        headers => $request->headers,
        body    => $request->content,
    );

    AnyEvent::HTTP::http_request $request->method, $request->uri, %options, sub {
        my ( $body, $header ) = @_;

        if ( defined $header->{'set-cookie'} ) {
            my @cookies;
            my $set_cookie = $header->{'set-cookie'};

            my @tmp = split( /,/, $set_cookie );
            while (@tmp) {
                my $t1 = shift @tmp;
                my $t2 = shift @tmp;

                push @cookies, "$t1,$t2";       # if defined $t1 && defined $t2;
            }

            $header->{'set-cookie'} = \@cookies;
        }

        my $res = HTTP::Response->new( $header->{Status}, $header->{Reason} );
        $res->request($request);
        $res->header(%$header);
        $self->cookies->extract_cookies($res);
        $cb->( $body, $header );
    };
} ## ---------- end sub request


no Moose;
__PACKAGE__->meta->make_immutable;

1;
