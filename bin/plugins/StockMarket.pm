package Hadouken::Plugin::StockMarket;
use strict;
use warnings;

use TryCatch;
use String::IRC;
use Encode qw( encode ); 
use JSON::XS qw( encode_json decode_json );
use Data::Printer alias => 'Dumper', colored => 1;


our $VERSION = '0.1';
our $AUTHOR = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return "Market commands: us, rtcom, agcom, tech, forex, q, fun";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "stockmarket";
}

sub command_regex {
    my $self = shift;

    return '(us|rtcom|tech|agcom|forex|q|quote|fun|\.\s.+?)';
}

# Return 1 if OK.
# 0 if does not pass ACL.
# command_run will only be called if ACL passes.
sub acl_check {
    my ($self, %aclentry) = @_;

    my $permissions = $aclentry{'permissions'};
    my $who = $aclentry{'who'};
    my $channel = $aclentry{'channel'};
    my $message = $aclentry{'message'};

    # Available acl flags:
    # Hadouken::BIT_ADMIN
    # Hadouken::BIT_WHITELIST
    # Hadouken::BIT_OP 
    # Hadouken::VOICE
    # Hadouken::BIT_BLACKLIST

    if($channel eq '#stocks' || $channel eq '#trading') {
        return 0;
    }

    # Make sure at least one of these flags is set.
    if($self->check_acl_bit($permissions, Hadouken::BIT_BLACKLIST)) {
        return 0;
    }
    #    || $self->check_acl_bit($permissions, Hadouken::BIT_WHITELIST)) {
    #|| $self->check_acl_bit($permissions, Hadouken::BIT_OP)) {

    #    return 1;
    #}

    return 1;
}


# Return 1 if OK (and then callback can be called)
# Return 0 and the callback will not be called.
sub command_run {
    my ($self,$nick,$host,$message,$channel,$is_admin,$is_whitelisted) = @_;
    my ($cmd, $arg) = split(/ /, lc($message),2);

    $cmd = 'q' if $cmd eq '.';
    warn "Command: $cmd";

    my $url = "http://quote.cnbc.com/quote-html-webservice/quote.htm?callback=webQuoteRequest&symbols=%s&symbolType=symbol&requestMethod=quick&exthrs=1&extMode=&fund=1&entitlement=0&skipcache=&extendedMask=1&partnerId=2&output=jsonp&noform=1";


    if($cmd eq 'us') {
        $url = sprintf "$url",'.IXIC|.SPX|.DJI|.NYA|.NDX';
    } elsif($cmd eq 'tech') {
        $url = sprintf "$url",'.SPLRCT';
    } elsif($cmd eq 'rtcom') {
        $url = sprintf "$url",'@CL.1|@GC.1|@SI.1|@NG.1';
    } elsif($cmd eq 'agcom') {
        $url = sprintf "$url",'@KC.1|@C.1|@CT.1|@S.1|@SB.1|@W.1|@CC.1';
    } elsif($cmd eq 'forex') {
        $url = sprintf "$url",'EUR=|GBP=|JPY=|USDCAD|CHF=|AUD=|EURJPY=|EURCHF=|EURGBP=';
    } elsif($cmd eq 'q' || $cmd eq 'quote' || $cmd eq 'fun') {

        return unless defined $arg && length $arg;

        my @z = split(/ /,uc($arg));

        my $q_string = '';
        foreach my $sym (@z) {
            chomp($sym);
            next unless length $sym;
            $q_string .= $sym.'|';
        }

        $q_string = substr($q_string, 0, -1);

        return unless length $q_string;

        $url = sprintf "$url","$q_string";
    }

    try {
        $self->asyncsock->get($url, sub {
                my ($body, $header) = @_;

                return unless defined $body && defined $header;

                my $json_object;

                if($body =~ m/^webQuoteRequest\((.*[^)]?)\)$/) {
                    $json_object = $1;
                } else {
                    warn "Could not parse json object.";
                    warn "Body:\n\n$body";
                    return 0;
                }

                my $json = $self->_jsonify($json_object);

                return unless defined $json && exists $json->{QuickQuoteResult}->{QuickQuote};

                my $summary;
                my @r;

                if(ref($json->{QuickQuoteResult}->{QuickQuote}) eq 'ARRAY') {
                    @r = @{$json->{QuickQuoteResult}->{QuickQuote}};
                } else {
                    @r = ();
                    push(@r,$json->{QuickQuoteResult}->{QuickQuote} );
                }

                for my $c (@r) {

                    next unless 
                    defined $c && exists $c->{name} && length $c->{name} && exists $c->{shortName} && exists $c->{last} && exists $c->{change} && exists $c->{change_pct};

                    my $name = $cmd eq 'tech' ? $c->{name} : $c->{shortName};

                    $name =~ s/DJIA/DOW/;
                    $name =~ s/NASDAQ/Nasdaq/;
                    $name =~ s/OIL/Crude/;
                    $name =~ s/NASD 100/NQ100/;
                    $name =~ s/S&P 500/S&P500/;

                    if($cmd eq 'rtcom' || $cmd eq 'agcom') {
                        $name = lc($name);
                        $name =~ s/(\w+)/\u$1/g;
                    }

                    my $wsid = $c->{issue_id}; # This is used when we make requests for {"title":"Show All","value":"*","issueType":"CS","symbol":"88160R101","wsodCompany":"2000016431"}

                    my $last = commify($c->{last});
                    my $change = $c->{change} || 0;
                    my $change_pct = $c->{change_pct} || 0;
                    my $change_pretty = String::IRC->new($change > 0 ? '+'.$change : $change);
                    my $change_pct_pretty = String::IRC->new($change_pct > 0 ? '+'.$change_pct.'%' : $change_pct.'%');

                    if($change > 0) {
                        $change_pretty->light_green;
                    } elsif($change < 0) {
                        $change_pretty->red;
                    } else {
                        $change_pretty->grey;
                    }

                    if($change_pct > 0) {
                        $change_pct_pretty->light_green;
                    } elsif($change_pct < 0) {
                        $change_pct_pretty->red;
                    } else {
                        $change_pct_pretty->grey; # neutral
                    }

                    $summary .= "$name: $last $change_pretty ($change_pct_pretty)  ";

                    if($cmd eq 'fun') {
                        my $company_name = $c->{name};
                        my $volume = $c->{volume};
                        my $open = $c->{open};
                        my $low = $c->{low};
                        my $high = $c->{high};
                        my $year_high = sprintf '%g', $c->{FundamentalData}{yrhiprice};
                        my $year_low = sprintf '%g', $c->{FundamentalData}{yrloprice};
                        my $yearly_range = $year_low.'-'.$year_high;
                        my $daily_range = $low.'-'.$high; #$open > $last ? $open.'-'.$last : $last.'-'.$open;


                        my $beta = sprintf '%.2f', $c->{FundamentalData}{beta};
                        my $eps = sprintf '%.2f', $c->{FundamentalData}{eps};
                        my $price_earnings = sprintf '%.3f', $c->{FundamentalData}{pe};
                        my $roe_ttm = sprintf '%.2f', $c->{FundamentalData}{ROETTM};
                        my $mktcapView = $c->{FundamentalData}{mktcapView} || 0;
                        my $revenuettmView = $c->{FundamentalData}{revenuettmView} || 0;
                        my $sharesoutView = $c->{FundamentalData}{sharesoutView} || 0;

                        my $fun = "$name ($company_name) ";
                        
                        $fun .= String::IRC->new("EPS:")->cyan;
                        $fun .= " $eps ";
                        $fun .= String::IRC->new("P\/E:")->cyan;
                        $fun .= " $price_earnings ";
                        $fun .= String::IRC->new("Mcap:")->cyan;
                        $fun .= " $mktcapView ";
                        $fun .= String::IRC->new("Revenue(TTM):")->cyan;
                        $fun .= " $revenuettmView ";
                        $fun .= String::IRC->new("Beta:")->cyan;
                        $fun .= " $beta ";
                        $fun .= String::IRC->new("Shares Outstanding:")->cyan;
                        $fun .= " $sharesoutView ";
                        $fun .= String::IRC->new("ROETTM:")->cyan;
                        $fun .= " $roe_ttm ";
                        # $fun .= "EPS: $eps P\/E: $price_earnings Mcap: $mktcapView Revenue(TTM): $revenuettmView Beta: $beta Shares Outstanding: $sharesoutView ROETTM: $roe_ttm";
                        
                        #$quote .= "Daily Range: (".$daily_range.") Yearly Range: (".$yearly_range.")";
                        $fun .= String::IRC->new("DIV:")->cyan if exists $c->{FundamentalData}{dividend};
                        $fun .= " ".sprintf '%g%%', $c->{FundamentalData}{dividend} if exists $c->{FundamentalData}{dividend};

                        $self->send_server (PRIVMSG => $channel, $fun);

                        # XOM - 91.9254  EPS: 7.949  P/E: 11.39  FPE: 13.72  P/S: 0.98  P/B: 2.12  BV: 42.646  50MA: 94.1711  200MA: 98.4349  DIV: %2.98  Beta: 0.9  Mcap: 389.3B  ROETTM: 19.61  Short Ratio: 3.10
                    }


                    if($cmd eq 'q' || $cmd eq 'quote') {
                        my $company_name = $c->{name};
                        my $volume = $c->{volume};
                        my $open = $c->{open};
                        my $low = $c->{low};
                        my $high = $c->{high};
                        my $year_high = sprintf '%g', $c->{FundamentalData}{yrhiprice};
                        my $year_low = sprintf '%g', $c->{FundamentalData}{yrloprice};
                        my $yearly_range = $year_low.'-'.$year_high;
                        my $daily_range = $low.'-'.$high; #$open > $last ? $open.'-'.$last : $last.'-'.$open;

                        my $quote = "$name ($company_name) Last: $last $change_pretty $change_pct_pretty (Vol: $volume) ";
                        $quote .= "Daily Range: (".$daily_range.") Yearly Range: (".$yearly_range.")";

                        my $curmktstatus = exists $c->{curmktstatus} ? $c->{curmktstatus} : '';

                        # warn Dumper($c);

                        if( $curmktstatus ne 'REG_MKT' && exists $c->{ExtendedMktQuote}) {
                            if(exists $c->{ExtendedMktQuote}{type} && $c->{ExtendedMktQuote}{type} eq 'PRE_MKT') {
                                my $last = commify($c->{ExtendedMktQuote}{last});
                                my $v = $c->{ExtendedMktQuote}{volume};
                                my $change = $c->{ExtendedMktQuote}{change};
                                my $change_pct = $c->{ExtendedMktQuote}{change_pct};
                                my $change_pretty = String::IRC->new($change > 0 ? '+'.$change : $change);
                                my $change_pct_pretty = String::IRC->new($change_pct > 0 ? '+'.$change_pct.'%' : $change_pct.'%');

                                if($change > 0) {
                                    $change_pretty->light_green;
                                } elsif($change < 0) {
                                    $change_pretty->red;
                                } else {
                                    $change_pretty->grey;
                                }

                                if($change_pct > 0) {
                                    $change_pct_pretty->light_green;
                                } elsif($change_pct < 0) {
                                    $change_pct_pretty->red;
                                } else {
                                    $change_pct_pretty->grey; # neutral
                                }
                                $quote .= " PreMarket $last $change_pretty $change_pct_pretty (Vol: $v)";
                            }
                        }

                        if($curmktstatus ne 'REG_MKT' && exists $c->{ExtendedMktQuote}) {
                            if(exists $c->{ExtendedMktQuote}{type} && $c->{ExtendedMktQuote}{type} eq 'POST_MKT') {
                                my $last = commify($c->{ExtendedMktQuote}{last});
                                my $v = $c->{ExtendedMktQuote}{volume};
                                my $change = $c->{ExtendedMktQuote}{change};
                                my $change_pct = $c->{ExtendedMktQuote}{change_pct};
                                my $change_pretty = String::IRC->new($change > 0 ? '+'.$change : $change);
                                my $change_pct_pretty = String::IRC->new($change_pct > 0 ? '+'.$change_pct.'%' : $change_pct.'%');

                                if($change > 0) {
                                    $change_pretty->light_green;
                                } elsif($change < 0) {
                                    $change_pretty->red;
                                } else {
                                    $change_pretty->grey;
                                }

                                if($change_pct > 0) {
                                    $change_pct_pretty->light_green;
                                } elsif($change_pct < 0) {
                                    $change_pct_pretty->red;
                                } else {
                                    $change_pct_pretty->grey; # neutral
                                }
                                $quote .= " PostMarket $last $change_pretty $change_pct_pretty (Vol: $v)";
                            }
                        }

                        $self->send_server (PRIVMSG => $channel, $quote);
                    } # // if($cmd eq 'q') {

                }

                if($cmd ne 'q' && $cmd ne 'quote' && $cmd ne 'fun') {
                    $summary =~ s/\s+$//;
                    $self->send_server (PRIVMSG => $channel, $summary) if defined $summary && length $summary;
                }
            });
    } 
    catch($e) {
        #warn $e;
    }

    return 1;
}

sub _jsonify {
    my $self = shift;
    my $arg = shift;
    my $hashref;
    try {
        $hashref = decode_json( encode("utf8", $arg) );
    } catch($e) {
        $hashref = undef;
    }
    return $hashref;
}

sub commify {
    local $_  = shift;
    1 while s/^(-?\d+)(\d{3})/$1,$2/;
    return $_;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Hadouken::Plugin::StockMarket - Stock market plugin.

=head1 DESCRIPTION

Stock market plugin for Hadouken.

=head1 AUTHOR

dek - L<http://dek.codes/>

=cut

