#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: test-gsearch.pl
#
#        USAGE: ./test-gsearch.pl  
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
#      CREATED: 06/13/2014 03:40:27 PM
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use utf8;

use REST::Google::Search;

#REST::Google::Search->http_referer('http://example.com');

my $res = REST::Google::Search->new(
    q => 'define: meaning',
);

die "response status failure" if $res->responseStatus != 200;

my $data = $res->responseData;

my $cursor = $data->cursor;

my $pages = $cursor->pages;

printf "current page index: %s\n", $cursor->currentPageIndex;

printf "estimated result count: %s\n", $cursor->estimatedResultCount;

my @results = $data->results;

foreach my $r (@results) {
    printf "\n";
    printf "title: %s\n", $r->title;
    printf "url: %s\n", $r->url;
}

warn "done";

