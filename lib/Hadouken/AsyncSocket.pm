package Hadouken::AsyncSocket;

use strict;
#use warnings;
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

use Data::UUID;

no strict "subs";
no strict "refs";
use feature qw( switch say );

if($] ge '5.018') {
    use experimental qw(lexical_subs smartmatch);
} else {
    warn "lexical_subs and smartwatch disabled";
}

our $VERSION = '0.03';

subtype 'Hadouken::AsyncSocket::Cookies' => as class_type('HTTP::Cookies');
coerce 'Hadouken::AsyncSocket::Cookies'  => from 'HashRef' =>
    via { HTTP::Cookies->new( %{$_} ) };

has timeout => ( is => 'rw', isa => 'Int', default => sub { 30 } );
has agent   => (
    is      => 'rw',
    isa     => 'Str',
    default => sub { 'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1)' }
);

has cookies => (
    is      => 'rw',
    isa     => 'Hadouken::AsyncSocket::Cookies',
    coerce  => 1,
    default => sub { HTTP::Cookies->new }
);

has proxypac  => ( is => 'rw', isa => 'Str', required => 0 );
has proxyhost => ( is => 'rw', isa => 'Str', required => 0 );
has proxyport => ( is => 'rw', isa => subtype( 'Int' => where { $_ > 0 } ), required => 0 );
has proxytype => ( is => 'rw', isa => enum( [qw(none https socks pac)] ), default => 'none' );
has useragent => (
    is       => 'rw',
    isa      => 'Str',
    required => 0,
    default  => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:73.0) Gecko/20100101 Firefox/73.0'
);

sub BUILD {
    my $self = shift;
    my $args = shift;

    $self->{debug}   = $args->{debug}   || 0;
    $self->{slave}   = $args->{slave}   || undef;
    $self->{hexdump} = $args->{hexdump} || 0;

    $self->{sock}   = undef;
    $self->{socket} = undef;

    # Global handlers to be propagated to all sub-classes.
    #$self->{handlers} => {};

    $self->{cv}       = AnyEvent->condvar( cb => sub { warn "done"; } );
    $self->{cbresult} = undef;

    my $uuid = Data::UUID->new;
    $self->{id} = $uuid->create_str();
    undef $uuid;
    $self->debug( "Hadouken::AsyncSocket initialized. UUID: " . $self->{id} );

} ## ---------- end sub BUILD

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

    $self->debug("SENDING REQUEST");
    $self->debug( "A" x 50 );

    $request->headers->user_agent( $self->agent );
    $self->cookies->add_cookie_header($request);

    my %options = (
        timeout   => $self->timeout,
        headers   => $request->headers,
        body      => $request->content,
        keepalive => 1,
        ssl_opts  => { verify_hostname => 0 },
        session   => $self->{id},               #re-use connection for this exact instance.
    );

    AnyEvent::HTTP::http_request $request->method, $request->uri, %options, sub {

        #my $a_res = AnyEvent::HTTP::Response->new(@_);
        #$self->hexdump(" Response", $a_res->header);

        #my $http_res = $a_res->to_http_message;

        #$self->debug("Status", $http_res->status_line);

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

# $request is an HTTP::Request
sub request2 {
    my ( $self, $request, $cb ) = @_;

    $self->debug("SENDING REQUEST");
    $self->debug( "A" x 50 );

    my %params;

    $params{session} = $self->{id};

    $request->header( 'user-agent' => $self->useragent );

    my $req = AnyEvent::HTTP::Request->new(
        $request,
        {
            cb     => sub { my ( $body, $header ) = @_; $cb->( $body, $header ); },
            params => \%params,
        }
    );

    $req->send();
} ## ---------- end sub request2

sub processPacket {
    my ( $self, $resp ) = @_;

    my $body = $resp->content;

    #use Data::Dumper;
    #print Dumper $resp;

    $self->debug( "SUCCESS " . $resp->is_success );
    $self->debug( "BODY IS " . length( ${ $resp->content_ref } ) . "BYTES!" );
    $self->debug( ${ $resp->content_ref } );

    #$self->{cv}->end();
    return 0;
} ## ---------- end sub processPacket

sub addHandler {
    my ( $self, %handlers ) = @_;

    foreach my $key ( keys %handlers ) {
        if ( ref( $handlers{$key} ) ne "CODE" ) {
            warn "Handlers must be CODE references.";
        }

        $self->{handlers}->{ lc($key) } = $handlers{$key};
        $self->debug("Global handler '$key' registered.");
    }
} ## ---------- end sub addHandler

sub addHandlers {
    return shift->addHandler(@_);
}

sub event {
    my ( $self, $name, @args ) = @_;

    $name = lc($name);

    if ( exists $self->{handlers}->{$name} ) {
        return $self->{handlers}->{$name}->( $self, @args );
    }
    elsif ( defined $self->{slave} ) {
        return $self->{slave}->event( $name, $self, @args );
    }

    return;
} ## ---------- end sub event

sub hexdump {
    my $self = shift;
    return unless $self->{hexdump};

    my ( $label, $data );
    if ( scalar(@_) == 2 ) {
        $label = shift;
    }
    $data = shift;

    say "$label:" if ($label);

    # Show 16 columns in a row.
    my @bytes  = split( //, $data );
    my $col    = 0;
    my $buffer = '';
    for ( my $i = 0; $i < scalar(@bytes); $i++ ) {
        my $char    = sprintf( "%02x", unpack( "C", $bytes[$i] ) );
        my $escaped = unpack( "C", $bytes[$i] );
        if ( $escaped < 20 || $escaped > 126 ) {
            $escaped = ".";
        }
        else {
            $escaped = chr($escaped);
        }

        $buffer .= $escaped;
        print "$char ";
        $col++;

        if ( $col == 8 ) {
            print "  ";
        }
        if ( $col == 16 ) {
            $buffer .= " " until length $buffer == 16;
            print "  |$buffer|\n";
            $buffer = "";
            $col    = 0;
        }
    }
    while ( $col < 16 ) {
        print "   ";
        $col++;
        if ( $col == 8 ) {
            print "  ";
        }
        if ( $col == 16 ) {
            $buffer .= " " until length $buffer == 16;
            print "  |$buffer|\n";
            $buffer = "";
        }
    }
    if ( length $buffer ) {
        print "|$buffer|\n";
    }
} ## ---------- end sub hexdump

sub debug {
    my ( $self, $line ) = @_;

    if ( !$self->{debug} ) {
        return;
    }

    say STDERR "$line";
} ## ---------- end sub debug


sub DESTROY {
    my $self = shift;
    $self->debug("DESTROY() enter.");
    $self->{handlers} = undef;
    $self->{id} = undef;
    $self->{cv} = undef;
}

no Moose;
#__PACKAGE__->meta->make_immutable;

1;

