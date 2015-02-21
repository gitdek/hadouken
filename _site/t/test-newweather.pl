use WWW::Wunderground::API;
use Data::Dumper;

print "Running...\n";

my $test = "weeeeeeeeeeee";

my @p =  ['hi','fuck'];
my @x =  ['fart','hi','bye','fuck'];


print Dumper(match(@p,'hi'));

#print Dumper($bbb);
#print Dumper(@bb);

print "Done.\n";

exit(0);

sub match {
    my $patterns = shift;
    $patterns = [ $patterns ] if(ref($patterns) ne 'ARRAY');
    #warn Dumper(@_);
    my @compiled = map qr/$_/i, @$patterns;
    grep {
    my $success = 0;
    foreach my $pat (@compiled) {
        $success = 1, last if /$pat/;
    }
    $success;
    } @_;
}

#using the options

my $wun = new WWW::Wunderground::API(
    location=>'33442',
    api_key=>'0152f00fc2831d35',
    auto_api=>1,
    #cache=>Cache::FileCache->new({ namespace=>'wundercache', default_expires_in=>2400 }) #A cache is probably a good idea. 
);



#Check the wunderground docs for details, but here are just a few examples 
print 'The temperature is: '.$wun->conditions->temp_f."\n"; 
print 'The rest of the world calls that: '.$wun->conditions->temp_c."\n"; 
print 'Record high temperature year: '.$wun->almanac->temp_high->recordyear."\n";
print "Sunrise at:".$wun->astronomy->sunrise->hour.':'.$wun->astronomy->sunrise->minute."\n";
print "Simple forecast:".$wun->forecast->simpleforecast->forecastday->[0]{conditions}."\n";
print "Text forecast:".$wun->forecast->txt_forecast->forecastday->[0]{fcttext}."\n";
print "Long range forecast:".$wun->forecast10day->txt_forecast->forecastday->[9]{fcttext}."\n";
print "Chance of rain three hours from now:".$wun->hourly->[3]{pop}."%\n";
print "Nearest airport:".$wun->geolookup->nearby_weather_stations->airport->{station}[0]{icao}."\n";

#Conditions is autoloaded into the root of the object
print "Temp_f:".$wun->temp_f."\n";








print Dumper($wun);
exit(0);

