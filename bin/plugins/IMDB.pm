package Hadouken::Plugin::IMDB;

use strict;
use warnings;

use TryCatch;
use Data::Dumper;
use IMDB::Film;

our $VERSION = '0.1';
our $AUTHOR = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return "Get imdb info by title";
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
    my ($self, %aclentry) = @_;

    my $permissions = $aclentry{'permissions'};

    if($self->check_acl_bit($permissions, Hadouken::BIT_ADMIN) 
        || $self->check_acl_bit($permissions, Hadouken::BIT_WHITELIST) 
        || $self->check_acl_bit($permissions, Hadouken::BIT_OP)) {

        return 1;
    }


    return 0;
}

# Return 1 if OK (and then callback can be called)
# Return 0 and the callback will not be called.
sub command_run {
    my ($self,$nick,$host,$message,$channel,$is_admin,$is_whitelisted) = @_;

    my ($cmd, $arg) = split(/ /, $message, 2); # DO NOT LC THE MESSAGE!

    return unless defined $arg;

    my $summary = $self->_imdb($arg);

    if(defined $summary && $summary ne '') {
        #my $weather_msg = "$arg -> $summary";
        #warn $weather_msg;
        $self->send_server (PRIVMSG => $channel, $summary);
    }

    return 1;
}

sub _imdb {
    my ($self, $title) = @_;

    return unless defined $title && $title ne '';

    my $summary = '';

    try {
        my $imdb = new IMDB::Film(crit => $title);    
        if($imdb->status) {
            $summary = "[imdb] Title: ".$imdb->title()." - ";
            $summary .= "Year: ".$imdb->year()." - " if defined $imdb->year && length $imdb->year;

            if(defined $imdb->rating && length $imdb->rating) {
                my $rating = $imdb->rating();
                $rating =~ s/\.?0*$//;
                $summary .= "Rating: ".$rating."/10 - ";
            }
            #warn "Plot Symmary: ".$imdb->plot()."\n";
            $summary .= "http://www.imdb.com/title/tt".$imdb->code."/";
        } else {
            warn "Something wrong: ".$imdb->error;
        }

        #warn Dumper($imdb);
    }
    catch($e) {
        $summary = '';

    }

    return $summary;
}


1;

