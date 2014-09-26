package Hadouken::Plugin::Weather;

use strict;
use warnings;

use Yahoo::Weather;
use TryCatch;
use Data::Dumper;
use String::IRC;

our $VERSION = '0.2';
our $AUTHOR = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return "Get weather info by weather <zip> or <location>. command alias: w";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "weather";
}

sub command_regex {
    my $self = shift;

    return '(weather|forecast|w)\s.+?';
    #return 'weather\s.+?';
}

# Return 1 if OK.
# 0 if does not pass ACL.
sub acl_check {
    my ($self, %aclentry) = @_;

    my $permissions = $aclentry{'permissions'};

#    if($self->check_acl_bit($permissions, Hadouken::BIT_ADMIN) 
#        || $self->check_acl_bit($permissions, Hadouken::BIT_WHITELIST) 
#        || $self->check_acl_bit($permissions, Hadouken::BIT_OP)) {
#
#        return 1;
#    }

    if($self->check_acl_bit($permissions,Hadouken::BIT_BLACKLIST)) {
        return 0;
    }

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

            # my $pretty_now = String::IRC->new('Now')->fuchsia;
            $summary = $ret->{'LocationDetails'}{'city'} if exists $ret->{'LocationDetails'}{'city'};
            $summary .= " ".$ret->{'LocationDetails'}{'region'} if exists $ret->{'LocationDetails'}{'region'};
            $summary .= "  ".$ret->{'CurrentObservation'}{'temp'}."°F" if exists $ret->{'CurrentObservation'}{'temp'};
            $summary .= " (".$ret->{'CurrentObservation'}{'text'}.")" if exists $ret->{'CurrentObservation'}{'text'};
            $summary .= " Visibility: ".$ret->{'Atmosphere'}{'visibility'}."mi" if exists $ret->{'Atmosphere'}{'visibility'};
            $summary .= " Humidity: ".$ret->{'Atmosphere'}{'humidity'}."%" if exists $ret->{'Atmosphere'}{'humidity'};
            $summary .= " Wind: ".$ret->{'WindDetails'}{'speed'}."mph" if exists $ret->{'WindDetails'}{'speed'};


#           $summary .= " Now -> Temp: ".$ret->{'CurrentObservation'}{'temp'} if exists $ret->{'CurrentObservation'}{'temp'};
#            $summary .= " Condition: ".$ret->{'CurrentObservation'}{'text'} if exists $ret->{'CurrentObservation'}{'text'};
#            $summary .= " Visibility: ".$ret->{'Atmosphere'}{'visibility'} if exists $ret->{'Atmosphere'}{'visibility'};
#            $summary .= " Humidity: ".$ret->{'Atmosphere'}{'humidity'} if exists $ret->{'Atmosphere'}{'humidity'};
            #


            my $pretty_second = String::IRC->new($ret->{'TwoDayForecast'}[1]{'day'})->navy;
            if (exists $ret->{'TwoDayForecast'}[1]{'high'} && exists $ret->{'TwoDayForecast'}[1]{'low'}) {
                $summary .= "  ".$pretty_second.": High: ".$ret->{'TwoDayForecast'}[1]{'high'}."°F Low: ".$ret->{'TwoDayForecast'}[1]{'low'}."°F";
                #$summary .= " - ".$ret->{'TwoDayForecast'}[1]{'day'}." -> High/Low: ".$ret->{'TwoDayForecast'}[1]{'high'}."/".$ret->{'TwoDayForecast'}[1]{'low'};
                $summary .= " (".$ret->{'TwoDayForecast'}[1]{'text'}.")" if exists $ret->{'TwoDayForecast'}[1]{'text'};
            }

            my $pretty_third = String::IRC->new($ret->{'TwoDayForecast'}[2]{'day'})->navy;
            if (exists $ret->{'TwoDayForecast'}[2]{'high'} && exists $ret->{'TwoDayForecast'}[2]{'low'}) {
                $summary .= "  ".$pretty_third.": High: ".$ret->{'TwoDayForecast'}[2]{'high'}."°F Low: ".$ret->{'TwoDayForecast'}[2]{'low'}."°F";
                #$summary .= " - ".$ret->{'TwoDayForecast'}[1]{'day'}." -> High/Low: ".$ret->{'TwoDayForecast'}[1]{'high'}."/".$ret->{'TwoDayForecast'}[1]{'low'};
                $summary .= " (".$ret->{'TwoDayForecast'}[2]{'text'}.")" if exists $ret->{'TwoDayForecast'}[2]{'text'};
            }


            #if (exists $ret->{'TwoDayForecast'}[2]{'high'} && exists $ret->{'TwoDayForecast'}[2]{'low'}) {
            #    $summary .= " - ".$ret->{'TwoDayForecast'}[2]{'day'}." -> High/Low: ".$ret->{'TwoDayForecast'}[2]{'high'}."/".$ret->{'TwoDayForecast'}[2]{'low'};
            #    $summary .= " Condition: ".$ret->{'TwoDayForecast'}[2]{'text'} if exists $ret->{'TwoDayForecast'}[2]{'text'};
            #}


            #warn Dumper($ret);
        }
    }
    catch($e) {
        $summary = '';

    }

    return $summary;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Hadouken::Plugin::Weather - Weather plugin.

=head1 DESCRIPTION

Weather forecast plugin for Hadouken.

=head1 AUTHOR

dek - L<http://dek.codes/>

=cut

