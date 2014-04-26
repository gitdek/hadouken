package Hadouken::Plugin::Weather;

use strict;
use warnings;

use Yahoo::Weather;
use TryCatch;

our $VERSION = '0.1';
our $AUTHOR = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return "Get weather info by weather <zip> or <location>";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "weather";
}

sub command_regex {
    my $self = shift;

    return 'weather\s.+?';
}

# Return 1 if OK.
# 0 if does not pass ACL.
sub acl_check {
    my ($self,$nick,$host,$message,$channel,$is_admin,$is_whitelisted) = @_;

    warn "$nick $host $message $channel, is_admin:$is_admin, is_whitelisted:$is_whitelisted\n";

    return 1;
}

# Return 1 if OK (and then callback can be called)
# Return 0 and the callback will not be called.
sub command_run {
    my ($self,$nick,$host,$message,$channel,$is_admin,$is_whitelisted) = @_;

    my ($cmd, $arg) = split(/ /, $message, 2); # DO NOT LC THE MESSAGE!

    return unless defined $arg;

    my $summary = $self->_weather($arg);

    if(defined $summary && $summary ne '') {
        my $weather_msg = "$arg -> $summary";
        $self->send_server (PRIVMSG => $channel, $weather_msg);
    }

    return 1;
}

sub _weather {
    my ($self, $location) = @_;

    return unless defined $location && $location ne '';

    unless(defined $self->{weatherclient}) {
        $self->{weatherclient} = Yahoo::Weather->new();
    }

    my $summary = '';
    try {
        my $ret = $self->{weatherclient}->getWeatherByLocation($location,'F');
        if(exists $ret->{'CurrentObservation'} )  {

            $summary = "Temp: ".$ret->{'CurrentObservation'}{'temp'};
            $summary .= " Condition: ".$ret->{'CurrentObservation'}{'text'};
        }
    }
    catch($e) {
        $summary = '';

    }

    return $summary;
}

1;

