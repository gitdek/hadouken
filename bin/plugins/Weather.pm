package Hadouken::Plugin::Weather;

use strict;
use warnings;

use Yahoo::Weather;
use TryCatch;
use Data::Dumper;

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

    my $summary = $self->_weather($arg);

    if(defined $summary && $summary ne '') {
        #my $weather_msg = "$arg -> $summary";
        #warn $weather_msg;
        $self->send_server (PRIVMSG => $channel, $summary);
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
        if(exists $ret->{'CurrentObservation'} && $ret->{'LocationDetails'} )  {

            $summary = $ret->{'LocationDetails'}{'city'} if exists $ret->{'LocationDetails'}{'city'};
            $summary .= " ".$ret->{'LocationDetails'}{'region'} if exists $ret->{'LocationDetails'}{'region'};

            $summary .= " Now -> Temp: ".$ret->{'CurrentObservation'}{'temp'} if exists $ret->{'CurrentObservation'}{'temp'};
            $summary .= " Condition: ".$ret->{'CurrentObservation'}{'text'} if exists $ret->{'CurrentObservation'}{'text'};
            $summary .= " Visibility: ".$ret->{'Atmosphere'}{'visibility'} if exists $ret->{'Atmosphere'}{'visibility'};
            $summary .= " Humidity: ".$ret->{'Atmosphere'}{'humidity'} if exists $ret->{'Atmosphere'}{'humidity'};

            if (exists $ret->{'TwoDayForecast'}[1]{'high'} && exists $ret->{'TwoDayForecast'}[1]{'low'}) {
                $summary .= " - ".$ret->{'TwoDayForecast'}[1]{'day'}." -> High/Low: ".$ret->{'TwoDayForecast'}[1]{'high'}."/".$ret->{'TwoDayForecast'}[1]{'low'};
                $summary .= " Condition: ".$ret->{'TwoDayForecast'}[1]{'text'} if exists $ret->{'TwoDayForecast'}[1]{'text'};
            }


            if (exists $ret->{'TwoDayForecast'}[2]{'high'} && exists $ret->{'TwoDayForecast'}[2]{'low'}) {
                $summary .= " - ".$ret->{'TwoDayForecast'}[2]{'day'}." -> High/Low: ".$ret->{'TwoDayForecast'}[2]{'high'}."/".$ret->{'TwoDayForecast'}[2]{'low'};
                $summary .= " Condition: ".$ret->{'TwoDayForecast'}[2]{'text'} if exists $ret->{'TwoDayForecast'}[2]{'text'};
            }


            warn Dumper($ret);
        }
    }
    catch($e) {
        $summary = '';

    }

    return $summary;
}

1;

