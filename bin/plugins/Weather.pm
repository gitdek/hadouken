package Hadouken::Plugin::Weather;

use strict;
use warnings;

use Hadouken ':acl_modes';

use Yahoo::Weather;
use TryCatch;

# use Data::Dumper;
use String::IRC;

our $VERSION = '0.3';
our $AUTHOR  = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return
        "Get weather info by weather <zip> or <location>. command alias: w. add -c for celsius";
} ## ---------- end sub command_comment

# Clean name of command.
sub command_name {
    my $self = shift;

    return "weather";
}

sub command_regex {
    my $self = shift;

    return '(weather|forecast|w)\s.+?';

    #return 'weather\s.+?';
} ## ---------- end sub command_regex

# Return 1 if OK.
# 0 if does not pass ACL.
sub acl_check {
    my ( $self, %aclentry ) = @_;

    my $permissions = $aclentry{'permissions'};

    #    if($self->check_acl_bit($permissions, Hadouken::BIT_ADMIN)
    #        || $self->check_acl_bit($permissions, Hadouken::BIT_WHITELIST)
    #        || $self->check_acl_bit($permissions, Hadouken::BIT_OP)) {
    #
    #        return 1;
    #    }

    if ( $self->check_acl_bit( $permissions, Hadouken::BIT_BLACKLIST ) ) {
        return 0;
    }

    return 1;
} ## ---------- end sub acl_check

# Return 1 if OK (and then callback can be called)
# Return 0 and the callback will not be called.
sub command_run {
    my ( $self, $nick, $host, $message, $channel, $is_admin, $is_whitelisted )
        = @_;

    my ( $cmd, $arg ) = split( / /, $message, 2 );    # DO NOT LC THE MESSAGE!

    return unless defined $arg;

    my $do_celsius = 0;

    if ( $arg =~ m/--?c/ ) {
        $do_celsius = 1;
        $arg =~ s/--?c//;
    }

    my $summary = $self->_weather( $arg, $do_celsius );

    if ( defined $summary && $summary ne '' ) {
        $self->send_server( PRIVMSG => $channel, $summary );
    }

    return 1;
} ## ---------- end sub command_run

sub _weather {
    my ( $self, $location, $do_celsius ) = @_;

    #$do_celsius = 0 unless defined $do_celsius;

    return unless defined $location && $location ne '';

    unless ( defined $self->{weatherclient} ) {
        $self->{weatherclient} = Yahoo::Weather->new();
    }

    my $summary = '';
    try {
        my $ret
            = $self->{weatherclient}->getWeatherByLocation( $location, 'F' );

        # warn Dumper($ret);

        if ( exists $ret->{'CurrentObservation'}
            && $ret->{'LocationDetails'} )
        {
            $summary = $ret->{'LocationDetails'}{'city'}
                if exists $ret->{'LocationDetails'}{'city'};
            $summary .= " " . $ret->{'LocationDetails'}{'region'}
                if exists $ret->{'LocationDetails'}{'region'};

            if ($do_celsius) {
                my $cel
                    = ( $ret->{'CurrentObservation'}{'temp'} - 32 ) * 5 / 9;
                my $cel_rounded = sprintf "%.1f", $cel;
                $summary .= "  " . $cel_rounded . "°C"
                    if defined $cel_rounded && $cel_rounded ne '';
            }
            else {
                $summary
                    .= "  " . $ret->{'CurrentObservation'}{'temp'} . "°F"
                    if exists $ret->{'CurrentObservation'}{'temp'};
            }

            $summary .= " (" . $ret->{'CurrentObservation'}{'text'} . ")"
                if exists $ret->{'CurrentObservation'}{'text'};

            if (   exists $ret->{'TwoDayForecast'}[0]{'high'}
                && exists $ret->{'TwoDayForecast'}[0]{'low'} )
            {
                if ($do_celsius) {
                    my $cel_low
                        = ( $ret->{'TwoDayForecast'}[0]{'low'} - 32 ) * 5 / 9;
                    my $cel_high
                        = ( $ret->{'TwoDayForecast'}[0]{'high'} - 32 )
                        * 5 / 9;
                    my $cel_low_rounded  = sprintf "%.1f", $cel_low;
                    my $cel_high_rounded = sprintf "%.1f", $cel_high;
                    $summary
                        .= " High: "
                        . $cel_high_rounded
                        . "°C Low: "
                        . $cel_low_rounded . "°C";
                }
                else {
                    $summary
                        .= " High: "
                        . $ret->{'TwoDayForecast'}[0]{'high'}
                        . "°F Low: "
                        . $ret->{'TwoDayForecast'}[0]{'low'} . "°F";
                }
            }

            $summary
                .= " Visibility: "
                . $ret->{'Atmosphere'}{'visibility'} . "mi"
                if exists $ret->{'Atmosphere'}{'visibility'}
                && $ret->{'Atmosphere'}{'visibility'} > 0;
            $summary .= " Humidity: " . $ret->{'Atmosphere'}{'humidity'} . "%"
                if exists $ret->{'Atmosphere'}{'humidity'};
            $summary .= " Wind: " . $ret->{'WindDetails'}{'speed'} . "mph"
                if exists $ret->{'WindDetails'}{'speed'};

            if ( exists $ret->{'WindDetails'}{'chill'} ) {
                if ($do_celsius) {
                    my $cel = ( $ret->{'WindDetails'}{'chill'} - 32 ) * 5 / 9;
                    my $cel_rounded = sprintf "%.1f", $cel;
                    $summary .= " Wind Chill: " . $cel_rounded . "°C"
                        if defined $cel_rounded && $cel_rounded ne '';
                }
                else {
                    $summary
                        .= " Wind Chill: "
                        . $ret->{'WindDetails'}{'chill'} . "°F"
                        if exists $ret->{'WindDetails'}{'chill'};
                }
            }

            my $pretty_second
                = String::IRC->new( $ret->{'TwoDayForecast'}[1]{'day'} )
                ->navy;
            if (   exists $ret->{'TwoDayForecast'}[1]{'high'}
                && exists $ret->{'TwoDayForecast'}[1]{'low'} )
            {

                if ($do_celsius) {
                    my $cel_low
                        = ( $ret->{'TwoDayForecast'}[1]{'low'} - 32 ) * 5 / 9;
                    my $cel_high
                        = ( $ret->{'TwoDayForecast'}[1]{'high'} - 32 )
                        * 5 / 9;
                    my $cel_low_rounded  = sprintf "%.1f", $cel_low;
                    my $cel_high_rounded = sprintf "%.1f", $cel_high;
                    $summary
                        .= "  "
                        . $pretty_second
                        . ": High: "
                        . $cel_high_rounded
                        . "°C Low: "
                        . $cel_low_rounded . "°C";
                }
                else {
                    $summary
                        .= "  "
                        . $pretty_second
                        . ": High: "
                        . $ret->{'TwoDayForecast'}[1]{'high'}
                        . "°F Low: "
                        . $ret->{'TwoDayForecast'}[1]{'low'} . "°F";
                }

                $summary .= " (" . $ret->{'TwoDayForecast'}[1]{'text'} . ")"
                    if exists $ret->{'TwoDayForecast'}[1]{'text'};
            }

            my $pretty_third
                = String::IRC->new( $ret->{'TwoDayForecast'}[2]{'day'} )
                ->navy;
            if (   exists $ret->{'TwoDayForecast'}[2]{'high'}
                && exists $ret->{'TwoDayForecast'}[2]{'low'} )
            {

                if ($do_celsius) {
                    my $cel_low
                        = ( $ret->{'TwoDayForecast'}[2]{'low'} - 32 ) * 5 / 9;
                    my $cel_high
                        = ( $ret->{'TwoDayForecast'}[2]{'high'} - 32 )
                        * 5 / 9;
                    my $cel_low_rounded  = sprintf "%.1f", $cel_low;
                    my $cel_high_rounded = sprintf "%.1f", $cel_high;
                    $summary
                        .= "  "
                        . $pretty_second
                        . ": High: "
                        . $cel_high_rounded
                        . "°C Low: "
                        . $cel_low_rounded . "°C";
                }
                else {
                    $summary
                        .= "  "
                        . $pretty_third
                        . ": High: "
                        . $ret->{'TwoDayForecast'}[2]{'high'}
                        . "°F Low: "
                        . $ret->{'TwoDayForecast'}[2]{'low'} . "°F";
                }

                $summary .= " (" . $ret->{'TwoDayForecast'}[2]{'text'} . ")"
                    if exists $ret->{'TwoDayForecast'}[2]{'text'};
            }
        }
    }
    catch($e) {
        $summary = '';

        }

        return $summary;
} ## ---------- end sub _weather

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

