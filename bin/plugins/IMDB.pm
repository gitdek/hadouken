package Hadouken::Plugin::IMDB;
use strict;
use warnings;

use Hadouken ':acl_modes';

use TryCatch;

#use Data::Dumper;
use IMDB::Film;

our $VERSION = '0.2';
our $AUTHOR  = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return "Perform IMDb search.";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "imdb";
}

sub command_regex {
    my $self = shift;

    return 'imdb\s.+?';
}

# Return 1 if OK.
# 0 if does not pass ACL.
sub acl_check {
    my ( $self, %aclentry ) = @_;

    my $permissions = $aclentry{'permissions'};

    #if($self->check_acl_bit($permissions, Hadouken::BIT_ADMIN)
    #    || $self->check_acl_bit($permissions, Hadouken::BIT_WHITELIST)
    #    || $self->check_acl_bit($permissions, Hadouken::BIT_OP)) {
    #
    #    return 1;
    #}

    if ( $self->check_acl_bit( $permissions, Hadouken::BIT_BLACKLIST ) ) {
        return 0;
    }

    return 1;
} ## ---------- end sub acl_check

# Return 1 if OK (and then callback can be called)
# Return 0 and the callback will not be called.
sub command_run {
    my ( $self, $nick, $host, $message, $channel, $is_admin, $is_whitelisted ) = @_;

    my ( $cmd, $arg ) = split( / /, $message, 2 );    # DO NOT LC THE MESSAGE!

    return unless defined $arg;

    my $summary = '';
    my $title   = $arg;

    try {
        my $imdb = new IMDB::Film( crit => $title );    #, search => 'find?tt=on;mx=20;q=');

        # Try searching if we do not get a result.
        unless ( $imdb->status ) {
            $imdb = new IMDB::Film(
                crit   => $title,
                search => 'find?tt=on;mx=20;q='
            );
        }

        if ( $imdb->status ) {
            $summary = "[imdb] " . $imdb->title() . " ";
            $summary .= "(" . $imdb->year() . ") - "
                if defined $imdb->year && length $imdb->year;

            if ( defined $imdb->rating && length $imdb->rating ) {
                my $rating = $imdb->rating();
                $rating =~ s/\.?0*$//;
                $summary .= $rating . "/10 - ";
            }

            my $storyline = $imdb->storyline();
            $storyline =~ s/Plot Summary \| Add Synopsis//;
            $summary .= "http://www.imdb.com/title/tt" . $imdb->code . "/";

            $self->send_server( PRIVMSG => $channel, $summary );

            # Wrap the summary, might be big.
            my $wrapped;
            ( $wrapped = $storyline ) =~ s/(.{0,300}(?:\s|$))/$1\n/g;
            my @lines = split( /\n/, $wrapped );
            my $cnt   = 0;
            foreach my $l (@lines) {
                next unless defined $l && length $l;
                next if $l eq 'Add Full Plot | Add Synopsis';

                $cnt++;
                $self->send_server(
                    PRIVMSG => $channel,
                    $cnt > 1 ? $l : "Summary - $l"
                );
            }
        }
        else {
            # warn "Something wrong: ".$imdb->error;
            #warn Dumper($imdb);
        }
    }
    catch ($e) {
        $summary = '';
    }

    return 1;
} ## ---------- end sub command_run

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Hadouken::Plugin::IMDB - IMDb plugin.

=head1 DESCRIPTION

IMDb plugin for Hadouken.

=head1 AUTHOR

dek <dek@whilefalsedo.com>

=cut

