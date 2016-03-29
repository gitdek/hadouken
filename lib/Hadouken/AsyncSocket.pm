package Hadouken::AsyncSocket;

use strict;
use warnings;
use utf8;

use AnyEvent::HTTP        ();
use HTTP::Request::Common ();
use HTTP::Request;
use HTTP::Response;
use HTTP::Cookies;
use Any::Moose;

our $VERSION = '0.2';

# This will handle asynchronous DNS, HTTP and other sockets.

has timeout => ( is => 'rw', isa => 'Int', default => sub { 30 } );
has agent => (
    is      => 'rw',
    isa     => 'Str',
    default => sub { 'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1)' }
);                                              #join "/", __PACKAGE__, $VERSION });
has cookie_jar => (
    is      => 'rw',
    isa     => 'HTTP::Cookies',
    default => sub { my $jar = HTTP::Cookies->new; $jar; }
);

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
    $self->cookie_jar->add_cookie_header($request);

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
        $self->cookie_jar->extract_cookies($res);
        $cb->( $body, $header );
    };
} ## ---------- end sub request

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;
