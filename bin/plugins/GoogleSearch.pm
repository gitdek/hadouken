package Hadouken::Plugin::GoogleSearch;

use strict;
use warnings;

use Hadouken ':acl_modes';

use HTML::Strip;
use String::IRC;
use REST::Google::Search;

REST::Google::Search->http_referer('http://hadouken.pw');

#use Data::Printer alias => 'Dumper', colored => 1;

use TryCatch;

our $VERSION = '0.2';
our $AUTHOR  = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return "google search. command aliases: google, goog. add results=N to display N results.";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "google";
}

sub command_regex {
    my $self = shift;

    return '(google|goog)\s.+?';
}

# Return 1 if OK.
# 0 if does not pass ACL.
sub acl_check {
    my ( $self, %aclentry ) = @_;

    my $permissions = $aclentry{'permissions'};

    if ( $self->check_acl_bit( $permissions, Hadouken::BIT_BLACKLIST ) ) {
        return 0;
    }

    # Or you can do it with the function Hadouken exports.
    # Make sure at least one of these flags is set.
    #if($self->check_acl_bit($permissions, Hadouken::BIT_ADMIN)
    #    || $self->check_acl_bit($permissions, Hadouken::BIT_WHITELIST)
    #    || $self->check_acl_bit($permissions, Hadouken::BIT_OP)) {

    #    return 1;
    #}

    return 1;
} ## ---------- end sub acl_check

# Return 1 if OK (and then callback can be called)
# Return 0 and the callback will not be called.
sub command_run {
    my ( $self, $nick, $host, $message, $channel, $is_admin, $is_whitelisted ) = @_;
    my ( $cmd, $arg ) = split( / /, lc($message), 2 );

    return
        unless ( defined($arg) && length($arg) );

    my $results = 1;

    try {
        if ( $arg =~ m/x=(\d+)/ ) {
            $results = $1;
            $results =~ s/^\s+//;
            $results =~ s/\s+$//;
            $arg =~ s/x=(\d+)//;
        }

        if ( $arg =~ m/results=(\d+)/ ) {
            $results = $1;
            $results =~ s/^\s+//;
            $results =~ s/\s+$//;
            $arg =~ s/results=(\d+)//;
        }

        if ( $results gt 4 || $results lt 1 ) {
            $results = 1;
        }

        $arg =~ s/^\s+//;
        $arg =~ s/\s+$//;

        my $res = REST::Google::Search->new( q => $arg, );

        if ( $res->responseStatus != 200 ) {
            warn "* Plugin GoogleSearch failed.";
            return 0;
        }

        my $data    = $res->responseData;
        my $cursor  = $data->cursor;
        my $pages   = $cursor->pages;
        my @results = $data->results;

        foreach my $r (@results) {
            next unless defined $r && defined $r->url && defined $r->title;

            my $hs         = HTML::Strip->new();
            my $clean_text = $hs->parse( $r->title );
            $hs->eof;

            my $summary = $clean_text . " - " . $r->url;
            $self->send_server( PRIVMSG => $channel, $summary );

            $results--;
            if ( $results lt 1 ) {
                last;
            }
        }

    }
    catch($e) {

        }

        return 1;
} ## ---------- end sub command_run

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Hadouken::Plugin::GoogleSearch - Google search plugin.

=head1 DESCRIPTION

Google search plugin for Hadouken.

=head1 AUTHOR

dek - L<http://dek.codes/>

=cut

