#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: test-lwpsearch.pl
#
#        USAGE: ./test-lwpsearch.pl  
#
#  DESCRIPTION: 
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: YOUR NAME (), 
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 06/13/2014 03:50:22 PM
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use utf8;

my $url = "http://glosbe.com/gapi/translate?from=eng&dest=eng&format=json&phrase=cat&pretty=true";

# Load our modules
# Please note that you MUST have LWP::UserAgent and JSON installed to use this
# You can get both from CPAN.
use LWP::UserAgent;
use JSON;

# Initialize the UserAgent object and send the request.
# Notice that referer is set manually to a URL string.
my $ua = LWP::UserAgent->new();
#$ua->default_header("HTTP_REFERER" => /* Enter the URL of your site here */);
my $body = $ua->get($url);

# process the json string
my $json = from_json($body->decoded_content);

# have some fun with the results
my $i = 0;
foreach my $result (@{$json->{tuc}->[0]->{meanings}}){
 $i++;
 print $i.". " . $result->{text} . "(" . $result->{language} . ")\n";
 # etc....
}
if(!$i){
 print "Sorry, but there were no results.\n";
}


