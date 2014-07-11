#!/usr/bin/perl

use strict;
use warnings;
use diagnostics;

use feature 'say';

use Test::More qw(no_plan);
use Data::Printer alias => 'Dumper';
use Regexp::Assemble;
use List::MoreUtils ':all';

diag( "Testing Regex Golf, Perl $], $^X" );

my @winners = ('The Phantom Menace','Attack of the Clones','Revenge of the Sith','A New Hope','The Empire Strikes Back','Return of the Jedi');
my @losers = ('The Wrath of Khan','The Search for Spock','The Voyage Home','The Final Frontier','The Undiscovered Country','Generations','First Contact','Insurrection','Nemesis');

# Return a set of all the strings that are matched by regex.
sub matches {
    my ($regex, $list) = @_;
    return grep { $_ =~ m/$regex/i } @$list;
}

# Return true if the regex matches all winners but no losers.
sub verify {
    my ($regex,$winners,$losers) = @_;

    my $missed_winners;
    my $matched_losers;

    for my $W ( @{$winners} ) {
        $missed_winners++ unless ($W =~ m/$regex/i );
    }

    for my $L ( @{$losers} ) {
        $matched_losers++ if ($L =~ m/$regex/i );
    }

    return not ($missed_winners or $matched_losers);    
}

# Return components that match at least one winner, but no loser.
sub regex_components {
    my ($winners,$losers) = @_;

    my @wholes = ();
    foreach my $winner (@$winners) {
        push @wholes,"\^$winner\$";
    }

    my @parts = ();
    for my $W ( @wholes ) {
        for my $S (subparts($W)) {
            for my $D (dotify($S)) {
                push @parts, $D;
            }
        }
    }

    my @p = ();
    for my $P (@parts) {
        if(!matches($P,$losers)) {
            push @p, $P;
        }
    }

    return uniq @p;
}

sub dotify {
    my ($part) = @_;
    return '' if !defined $part || $part eq '';
    my @list;
    for my $rest ( dotify( (split //, substr $part,1 ))  ) {
        for my $c ( split //, replacements( substr $part,0,1 )  ) {
            push @list, "$c$rest";
        }
    }
    return @list;
}

sub replacements {
    my ($char) = @_;
    if ($char eq '^' or $char eq '$') {
        return $char;
    } else {
        return $char . '.';
    }
}

sub subparts {
    my ($word) = @_;

    my @list;
    for my $i ( 0 .. (length($word) - 1) ) {
        for my $n ( 1 .. 4 ) {
            push @list, substr($word,$i,$i+$n);
        }
    }

    return uniq @list;
}

sub largest_value {
    my $hash = shift;
    keys %$hash;

    my ($large_key, $large_val) = each %$hash;

    while (my ($key, $val) = each %$hash) {
        if ($val > $large_val) {
            $large_val = $val;
            $large_key = $key;
        }
    }
    return $large_key;
}

# Find a regex to match A but not B, and vice-versa.  Print summary.
sub findboth {
    my($A,$B) = @_;
    
    my $solution = findregex($A,$B);
    is(verify($solution,$A,$B), 1, 'findboth verify W-L');
    my $ratio =  length("\^(" .join("\|",@$A). ")\$") / (length($solution));
    printf "%3d chars, %4.1f ratio, %2d winners %s: %s\n", length($solution), $ratio , length($A), "W-L", $solution;
    
    $solution = findregex($B,$A);
    is(verify($solution,$B,$A), 1, 'findboth verify L-W');
    $ratio =  length("\^(" .join("\|",@$B). ")\$") / (length($solution));
    printf "%3d chars, %4.1f ratio, %2d winners %s: %s\n", length($solution), $ratio , length($B), "L-W", $solution;
}

# Find regex that matches all winners and no losers.
sub findregex {
    my ($winners,$losers) = @_;

    my @pool = regex_components($winners, $losers);
    my @solution = ();

    my $bestscore = sub {
        my ($PI) = @_;
        my %scores;
        for my $poolitem (@$PI) {
            my @M = matches($poolitem,$winners);
            my $score = 4 * scalar(@M) - length($poolitem);
            $scores{$poolitem} = $score;
        }

        my $bestie = largest_value( \%scores );
        return $bestie;
    };

    my @winners_copy;
    @winners_copy = @$winners;

    while( @winners_copy ) {
        my $best = $bestscore->(\@pool);
        push(@solution,$best);
        
        my %matches = map {$_ => 1} matches($best,\@winners_copy);
        my @filtered = grep { !exists $matches{$_}} @winners_copy;
        @winners_copy = @filtered;

        my @newpool = ();
        for my $r (@pool) {
            push(@newpool,$r) if matches($r,\@winners_copy);
        }
        @pool = @newpool;
    }

    return join("\|", @solution);
}

sub genregex {
    my ($list) = @_;
    
    my $r = Regexp::Assemble->new;
    
    for (@$list) {
        chomp($_);
        $r->add("^\Q$_\E\$");
    }
    $_ = $r->as_string;
    s/\(\?:/(/g;
    return $_;
}




say "winners: ". join(', ', @winners);
say "losers: ". join(', ', @losers);

findboth( \@winners, \@losers );

#my $G1 = findregex( \@winners, \@losers );
# my $C1 = 'er|ti|n$|Co| F|.y|is';
my $G1 = ' t|^A|Ph|B.';
is(verify($G1, \@winners, \@losers), 1, "$G1 matches winners and NOT losers");

my $R1 = 'M | [TN]|B';
my $R2 = ' T|E.P| N';
is(verify($R1, \@winners, \@losers), 1, "$R1 matches winners and not losers");
is(verify($R2, \@winners, \@losers), 1, "$R2 matches winners and not losers");
is(verify('a+b+', ['ab', 'aaabb'], ['a', 'bee', 'a b']), 1,'verify');

