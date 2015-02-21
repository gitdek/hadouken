#!/usr/bin/perl

use warnings;

use HTML::TableContentParser;
use Data::Dumper;
use JSON;

my $input;

while(<>){        #reads lines until end of file or a Control-D
    #print "$_";    #prints lines back out
    $input .= "$_";
}
#my $input = @ARGV ? shift(@ARGV) : <STDIN>;
#warn $input;

$tcp = HTML::TableContentParser->new;
$tables = $tcp->parse($input);

#print Dumper($tables);

my %scores;
my %scores2;

$table = @$tables[1];

#foreach $table (@$tables) {

my $r = 0;


for $row (@{$table->{rows}}) {
    next if (++$r == 1); # HEADER.

    # Rank Player Score Percent Of Total
    (my $a = $row->{cells}[0]->{data}) =~ s|<.+?>||g;
    (my $b = $row->{cells}[1]->{data}) =~ s|<.+?>||g;
    (my $c = $row->{cells}[2]->{data}) =~ s|<.+?>||g;
    (my $d = $row->{cells}[3]->{data}) =~ s|<.+?>||g;

    next if $b eq 'channel-total';
    
    next unless $c =~ /^-?\d+$/; # Make sure integer.
    
#    print "$a $b $c $d";

    $scores{player}{$b}{rank} = $a;
    $scores{player}{$b}{score} = $c;
    
    $scores2{$b}{score} = $c;
    $scores2{$b}{rank} = $a;
}

my $new_scores = JSON->new->allow_nonref->encode(\%scores2);

open(FILE,">scores.json");
print FILE $new_scores;
close(FILE);

my $json_data = JSON->new->allow_nonref->pretty->encode(\%scores);

my $i = 0;
my @rankings = sort { $scores{player}{$b}{score} <=> $scores{player}{$a}{score} } keys $scores{player};

for my $p (@rankings) {
    $scores{player}{$p}{rank} = ++$i;
}

my $top_N = 10;
for my $u ( 0 .. $#rankings) {
    last if --$top_N < 0;
    print int($u + 1) . "\t".$rankings[$u]."\n";
}

my $user = 'dwarf';
my $user_rank = $scores{player}{$user}{rank};

warn "$user is ". int($user_rank);

@rankings = splice @rankings,0,1;

my $points_needed;
my $points_ahead;
my $pos_prev = $rankings[$user_rank - 2] || 0;
my $pos_next = $rankings[int($user_rank + 2)] || 0;

warn $pos_prev;
warn $pos_next;

if($user_rank == 1) {
    $points_ahead = $scores{player}{$user}{score} - $scores{player}{$pos_next}{score};
    warn "$user is $points_ahead points ahead for keeping 1st place ";
}
else {
    $points_needed = $scores{player}{$pos_prev}{score} - $scores{player}{$user}{score};
    warn "$user needs $points_needed points to take over position ". $scores{player}{$pos_prev}{rank};
}



#warn "done";
#exit(0);

#warn $input;


