#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: test-tokenparse.pl
#
#        USAGE: ./test-tokenparse.pl  
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
#      CREATED: 06/14/2014 11:53:57 AM
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use utf8;

use HTML::TokeParser;
use YAML;
use Data::Dumper;

my $crap = q{<div class="boxyPaddingBig">
<h2>Quote of the Day</h2>
<span class="bqQuoteLink"><a title="view quote" href="/quotes/quotes/r/rebeccawes145773.html" onclick="qCl('qotd','/quotes_of_the_day','/quotes/quotes/r/rebeccawes145773','1')">It is always one's virtues and not one's vices that precipitate one into disaster.</a></span><br>
<div class="bq-aut"><a title="view author" href="/quotes/authors/r/rebecca_west.html" onclick="aCl('qotd','/quotes_of_the_day','/quotes/authors/r/rebecca_west','1')">Rebecca West</a></div>
</div>};


my $html2 = q{<div><div class="meaning">To chill out, calm down and take a break.</div></div>};
my $html = q{<img src="random.jpg" class="someClass" id="someId" alt="test"/>};
my $parser = HTML::TokeParser->new( \$crap );

my $qotd = undef;
my $author = undef;

while (my $token = $parser->get_tag('div')) {
# 
    next unless (defined $token->[1] && exists $token->[1]{class});
    
    my $blah =  $token->[1]{class};

    #if ($blah eq 'bqQuoteLink') {
    #    $qotd = $parser->get_trimmed_text("/div");
    #}
    
    #if ($blah eq 'bq-aut') {
    #    $author = $parser->get_trimmed_text("/div");
    #}
    
    if (defined($author) && defined($qotd) && length($author) && length($qotd)) {
        warn $author;
        warn $qotd;
        last;
    }

    my $text = $parser->get_trimmed_text("/div");

    warn $text;
    print Dumper $blah;
}
