#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: test-gzip.pl
#
#        USAGE: ./test-gzip.pl  
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
#      CREATED: 06/13/2014 06:47:26 PM
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use utf8;

use IO::Compress::Gzip qw(gzip $GzipError) ;
use MIME::Base64;
my $foo = "H" x 200;

my $compressed;

if(gzip \$foo => \$compressed ){
    # Compressed version of $foo stored in $compressed
    warn "DONE!";
    
    my $b64 = MIME::Base64::encode_base64($compressed);

    warn length($b64);
    warn length($compressed);       
    warn length($foo);

    #   }
}

warn "exiting...";


