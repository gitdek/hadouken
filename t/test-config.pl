#!/usr/bin/perl

use strict;
use warnings;

use JSON::PP ();
use Config::General;
use Data::Printer alias => 'Dumper', colored => 1;
#use Data::Dumper;
use Clone qw(clone);

no strict 'refs';

use Redis;
use Redis::List;
use Redis::Hash;

use JSON::Parse 'parse_json';

my $config_filename = '/home/dek/projects/perl/ircbot/example.hadouken.conf';

my $conf = Config::General->new(-ConfigFile => $config_filename, -ExtendedAccess => 1, -AllowMultiOptions => 1,-AutoTrue => 1,-ApacheCompatible => 1,-MergeDuplicateBlocks => 1);

my %config = $conf->getall;

my $content = $conf->save_string(\%config);

#warn $content;
#exit;

#my $individual = $conf->obj("server");
#my %part = $individual->getall;
#print Dumper(%part);

my $individual = $conf->obj("server");
 foreach my $person ($conf->keys("server")) {
    my $man = $individual->obj($person);
    my %g=$man->getall;
    #print Dumper(\%g),"\n\n";
    #print "$person is " . $man->value("age") . " years old\n";
}

my $json = JSON::PP->new->canonical(1)->allow_nonref(1)->allow_barekey->utf8->pretty->encode(\%config);


my $redis = Redis->new;

#my $my_hash;

#my %fart = $conf->getall;

#print Dumper(%fart);

#my $my_hash = clone(\%fart);

my $fart = ();

tie %{$fart}, 'Redis::Hash', 'my_hash';

my $wee = JSON::PP->new->canonical(1)->allow_nonref(1)->allow_barekey->utf8->pretty->encode(\%config);

$fart = parse_json($wee);

#while( my ( $key, $val ) = each %fart ) { 
	
#	delete $fart{$key};
#}


print Dumper($fart);

#%fart = $conf->getall;

#$fart{'hello'} = 1;

#delete $my_hash{test};

#tie my @my_list, 'Redis::List', 'list_name3';

#print Dumper(%config);

#warn "Goodbye!";

#print Dumper($json);
#print $json;
#print $json->encode(\%config);

1;