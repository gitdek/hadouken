package Hadouken::Plugin::StockMarket;
use strict;
use warnings;

use Hadouken ':acl_modes';

use TryCatch;
use String::IRC;
use Encode qw( encode );
use JSON::XS qw( encode_json decode_json );
use URI::Escape;
use HTML::TokeParser;
use Text::Unidecode;
#use Data::Printer alias => 'Dumper', colored => 1;

# use CHI;

our $VERSION = '0.6';
our $AUTHOR  = 'dek';

our $mktmovers_nasdaq =
    'B64ENCeyJzeW1ib2wiOiJVUztDT01QIiwiY291bnQiOiIyMCIsImNoYXJ0IjoiYm90aCIsInJlZ2lvbiI6IiJ9';
our $mktmovers_sp500 =
    'B64ENCeyJzeW1ib2wiOiJVUztTUFgiLCJjb3VudCI6IjIwIiwiY2hhcnQiOiJib3RoIiwicmVnaW9uIjoiIn0=';
our $mktmovers_dow =
    'B64ENCeyJzeW1ib2wiOiJVUyZESkkiLCJjb3VudCI6IjIwIiwiY2hhcnQiOiJib3RoIiwicmVnaW9uIjoiIn0=';

our $USE_NOTICE = 0;
our $SEND_CMD = $USE_NOTICE ? 'NOTICE' : 'PRIVMSG';

# Description of this command.
sub command_comment {
    my $self = shift;

    my $ret = '';
    $ret .=
        "List of commands: agcom, asia, b, bonds, etfs, eu, europe, fforex, footsie, forex, ftse, fun, fus, fx, movers, oil, q, quote, rtcom, tech, us, vix, xe, book, nfo, info, news.\n";
    $ret .=
        "  movers [exchange] - exchanges: sp500, dow, nasdaq - See biggest gainers/losers of the day.\n";
    $ret .= "  xe [currency_a] [currency_b] [amount] - xe.com currency conversion.\n";
    $ret .= "  fforex/ffx - Forex futures.\n";
    $ret .= "  nfo [symbol] - Financial information in long form.\n";
    $ret .= "  info [symbol] - Financial information in even longer form.\n";
    $ret .= "  news [symbol] - Search news headlines for symbol.\n";

    return $ret;
} ## ---------- end sub command_comment

# Clean name of command.
sub command_name {
    my $self = shift;

    return "stockmarket";
}

sub command_regex {
    my $self = shift;

    # us = us market
    # fus = futures us market
    # etfs = exchange traded funds
    # eu = eu market
    # europe = alias for eu
    # asia = asia market
    # ftse = 100 companies on london exchange with highest capitalization
    # footsie = alias for ftse
    # rtcom = crude, gold, silver, nat gas
    # oil = shortcut to crude oil quote
    # tech = S&P 500 Information Technology Sector
    # agcom = AGRICULTURE FUTURES
    # fx = forex / currencies
    # forex = alias for fx
    # ffx = forex futures
    # fforex = alias for ffx
    # q = query for a quote
    # quote = alias for q
    # fun = fundamentals lookup
    # vix = CBOE Volatility Index
    # b = bonds
    # bonds = alias for b
    # movers = top movers/losers of the S&P 500
    # xe = XE.com Currency Converter
    # book = get order book information of stock.
    # nfo = Financial summary in long form.
    # info = Financial summary in longer form.
    # news = Search for news headlines.
    return
        '(test|news|return|xe|movers|us|fus|etfs|eu|europe|asia|ftse|footsie|rtcom|oil|tech|agcom|fx|forex|ffx|fforex|q|quote|fun|vix|b|bonds|book|nfo|info|\.(?!\.))';
} ## ---------- end sub command_regex

# Return 1 if OK.
# 0 if does not pass ACL.
# command_run will only be called if ACL passes.
sub acl_check {
    my ( $self, %aclentry ) = @_;

    my $permissions = $aclentry{'permissions'};
    my $who         = $aclentry{'who'};
    my $channel     = $aclentry{'channel'};
    my $message     = $aclentry{'message'};

    # Available acl flags:
    # Hadouken::BIT_ADMIN
    # Hadouken::BIT_WHITELIST
    # Hadouken::BIT_OP
    # Hadouken::VOICE
    # Hadouken::BIT_BLACKLIST

    # Make sure at least one of these flags is set.
    if ( $self->check_acl_bit( $permissions, Hadouken::BIT_BLACKLIST ) ) {
        return 0;
    }

    return 1;

} ## ---------- end sub acl_check

# Return 1 if OK (and then callback can be called)
# Return 0 and the callback will not be called.
sub command_run {
    my ( $self, $nick, $host, $message, $channel, $is_admin, $is_whitelisted ) = @_;
    my ( $cmd, $arg ) = split( / /, lc($message), 2 );

    return unless defined $cmd && length $cmd;

    $cmd = 'q' if $cmd eq '.';

    warn "* StockMarket command: $cmd";

    #$self->quoteminimal($channel,$nick,$arg) if cmd eq 'test';

    if ( $cmd eq 'test' ) {

        my $ret = $self->quoteminimal( $channel, $nick, ['AAPL','YHOO'] );

        return 1;
    }

    if ( $cmd eq 'news' ) {

        return unless defined $arg;

        my @z = split( / /, uc($arg) );
        my $symbols = join( ',', @z );

        #my $ret = $self->quoteminimal($channel,$nick,$arg);
        my $ret = $self->news_search( $channel, $nick, $symbols );

        return 1;
    }

    if ( $cmd eq 'nfo' || $cmd eq 'info' ) {
        return unless defined $arg && length $arg;

        my @z = split( / /, uc($arg) );

        foreach my $nfo (@z) {

            next unless length $nfo;

            my $ret = $self->finances( $channel, $nick, uc($nfo), $cmd eq 'info' );

        }

        return 1;
    }

    if ( $cmd eq 'xe' ) {

        my ( $from, $dest, $amount ) = split( / /, lc($arg) );

        $amount = 1 unless defined $amount;

        my $ret = $self->currency_convert( $channel, $from, $dest, $amount );

        return $ret;
    }

    if ( $cmd eq 'return' ) {
        my ( $x, $y ) = split( / /, lc($arg) );

        my $ret = ( ( $y - $x ) / $x ) * 100;

        return 0 unless defined $ret;

        warn "return $ret";

        my $ret_clean = sprintf '%g%%', $ret;

        $self->send_server( $SEND_CMD => $channel, $ret_clean );

        return 1;
    }

    if ( $cmd eq 'book' ) {

        return unless defined $arg;

        my @z = split( / /, uc($arg) );

        foreach my $b (@z) {

            next unless length $b;

            my $ret = $self->stock_book( $channel, uc($b) );
        }

        return 1;

        #return $ret;
    }

    if ( $cmd eq 'movers' ) {
        my $mkt = '';
        $mkt = $mktmovers_dow    if lc $arg eq 'dow';
        $mkt = $mktmovers_nasdaq if lc $arg eq 'nasdaq';
        $mkt = $mktmovers_sp500  if lc $arg eq 'sp500' || lc $arg eq 'es';

        return $self->market_movers( $channel, $mkt );
    }

    my $url =
        "http://quote.cnbc.com/quote-html-webservice/quote.htm?callback=webQuoteRequest&symbols=%s&symbolType=symbol&requestMethod=quick&exthrs=1&extMode=&fund=1&entitlement=1&skipcache=&extendedMask=1&partnerId=2&output=jsonp&noform=1";

    if ( $cmd eq 'us' ) {
        $url = sprintf "$url", '.IXIC|.SPX|.DJI|.NYA|.NDX|.RUT';
    }
    elsif ( $cmd eq 'fus' ) {                   # US Futures.
        $url = sprintf "$url", '@DJ.1|@SP.1|@ND.1|@MD.1|@TFS.1';
    }
    elsif ( $cmd eq 'etfs' ) {
        $url = sprintf "$url", 'SPY|QQQ|DIA|EEM|VTI|IVV|MDY|EFA';
    }
    elsif ( $cmd eq 'asia' ) {
        $url = sprintf "$url", '.N225|.HSI|.SSEC|.AXJO|.FTSTI';
    }
    elsif ( $cmd eq 'eu' || $cmd eq 'europe' ) {
        $url = sprintf "$url", '.GDAXI|.FTSE|.FCHI';
    }
    elsif ( $cmd eq 'ftse' || $cmd eq 'footsie' ) {
        $url = sprintf "$url", '.FTSE';
        $cmd = 'q';
    }
    elsif ( $cmd eq 'b' || $cmd eq 'bonds' ) {
        $url = sprintf "$url", 'US2Y|US5Y|US10Y|US30Y';
    }
    elsif ( $cmd eq 'vix' ) {
        $url = sprintf "$url", '.VIX';
        $cmd = 'q';
    }
    elsif ( $cmd eq 'tech' ) {
        $url = sprintf "$url", '.SPLRCT';
        $cmd = 'q';
    }
    elsif ( $cmd eq 'oil' ) {
        $url = sprintf "$url", '@CL.1';
        $cmd = 'q';
    }
    elsif ( $cmd eq 'rtcom' ) {
        $url = sprintf "$url", '@CL.1|@GC.1|@SI.1|@NG.1';
    }
    elsif ( $cmd eq 'agcom' ) {
        $url = sprintf "$url", '@KC.1|@C.1|@CT.1|@S.1|@SB.1|@W.1|@CC.1';
    }
    elsif ( $cmd eq 'forex' || $cmd eq 'fx' ) {
        $url = sprintf "$url", 'EUR=|GBP=|JPY=|CNY=|CAD=|CHF=|AUD=|EURJPY=|EURCHF=|EURGBP=';
    }
    elsif ( $cmd eq 'fforex' || $cmd eq 'ffx' ) {
        $url = sprintf "$url", '@DX.1|@URO.1|@JY.1|@BP.1|@AD.1|@CD.1|@SF.1';
    }
    elsif ( $cmd eq 'q' || $cmd eq 'quote' || $cmd eq 'fun' ) {

        return unless defined $arg && length $arg;

        my @z = split( / /, uc($arg) );

        my $q_string = '';
        foreach my $sym (@z) {
            chomp($sym);
            next unless length $sym;
            $q_string .= $sym . '|';
        }

        $q_string = substr( $q_string, 0, -1 );

        return unless length $q_string;

        $url = sprintf "$url", "$q_string";
    }
    else {

        return 0;
    }

    try {
        $self->asyncsock->get(
            $url,
            sub {
                my ( $body, $header ) = @_;

                return unless defined $body && defined $header;

                my $json_object;

                if ( $cmd eq 'movers' ) {
                    return unless defined $body && length $body;

                    my $mkt = '';
                    $mkt = $mktmovers_dow    if lc $arg eq 'dow';
                    $mkt = $mktmovers_nasdaq if lc $arg eq 'nasdaq';
                    $mkt = $mktmovers_sp500  if lc $arg eq 'sp500' || lc $arg eq 'es';

                    return $self->market_movers( $channel, $mkt );
                }

                if ( $body =~ m/^webQuoteRequest\((.*[^)]?)\)$/ ) {
                    $json_object = $1;
                }
                else {
                    warn "Could not parse json object.";
                    warn "Body:\n\n$body";
                    return 0;
                }

                my $json = $self->_jsonify($json_object);

                return unless defined $json && exists $json->{QuickQuoteResult}->{QuickQuote};

                my $summary;
                my @r;

                if ( ref( $json->{QuickQuoteResult}->{QuickQuote} ) eq 'ARRAY' ) {
                    @r = @{ $json->{QuickQuoteResult}->{QuickQuote} };
                }
                else {
                    @r = ();
                    push( @r, $json->{QuickQuoteResult}->{QuickQuote} );
                }

                for my $c (@r) {

                    next
                        unless defined $c
                        && exists $c->{name}
                        && length $c->{name}
                        && exists $c->{shortName}
                        && exists $c->{last}
                        && exists $c->{change}
                        && exists $c->{change_pct};

                    warn Dumper($c);

                    my $name = $cmd eq 'tech' ? $c->{name} : $c->{shortName};

                    $name =~ s/DJIA/DOW/;
                    $name =~ s/NASDAQ/Nasdaq/;
                    $name =~ s/OIL/Crude/;
                    $name =~ s/NASD 100/NQ100/;
                    $name =~ s/S&P 500/S&P500/;
                    $name =~ s/CAC 40/CAC40/;
                    $name =~ s/CNBC 100/CNBC100/;

                    if ( $cmd eq 'rtcom' || $cmd eq 'agcom' ) {
                        $name = lc($name);
                        $name =~ s/(\w+)/\u$1/g;
                    }

                    my $wsid       = $c->{issue_id};
                    my $last       = commify( $c->{last} );
                    my $change     = $c->{change} || 0;
                    my $change_pct = sprintf '%.2f', $c->{change_pct} || 0;
                    my $change_pretty =
                        String::IRC->new( $change > 0 ? '+' . $change : $change );
                    my $change_pct_pretty = String::IRC->new(
                        $change_pct > 0 ? '+' . $change_pct . '%' : $change_pct . '%' );

                    if ( $change > 0 ) {
                        $change_pretty->light_green;
                    }
                    elsif ( $change < 0 ) {
                        $change_pretty->red;
                    }
                    else {
                        $change_pretty->pink;
                    }

                    if ( $change_pct > 0 ) {
                        $change_pct_pretty->light_green;
                    }
                    elsif ( $change_pct < 0 ) {
                        $change_pct_pretty->red;
                    }
                    else {
                        $change_pct_pretty->pink;    # neutral
                    }

                    $summary .= "$name: $last $change_pretty ($change_pct_pretty)  ";

                    if ( $cmd eq 'fun' ) {
                        my $company_name = $c->{name};
                        my $volume       = $c->{volume};
                        my $open         = $c->{open} || 0;
                        my $low          = $c->{low} || 0;
                        my $high         = $c->{high} || 0;
                        my $year_high    = sprintf '%g', $c->{FundamentalData}{yrhiprice};
                        my $year_low     = sprintf '%g', $c->{FundamentalData}{yrloprice};
                        my $yearly_range = $year_low . '-' . $year_high;
                        my $daily_range  = $low . '-'
                            . $high;            #$open > $last ? $open.'-'.$last : $last.'-'.$open;

                        my $beta           = sprintf '%g', $c->{FundamentalData}{beta};
                        my $eps            = sprintf '%g', $c->{FundamentalData}{eps};
                        my $price_earnings = sprintf '%g', $c->{FundamentalData}{pe};
                        my $roe_ttm        = sprintf '%g', $c->{FundamentalData}{ROETTM};
                        my $mktcapView     = $c->{FundamentalData}{mktcapView}     || 0;
                        my $revenuettmView = $c->{FundamentalData}{revenuettmView} || 0;
                        my $sharesoutView  = $c->{FundamentalData}{sharesoutView}  || 0;
                        my $fun            = "$name ($company_name) ";

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
                        $fun .= String::IRC->new("DIV:")->cyan
                            if exists $c->{FundamentalData}{dividend};
                        $fun .= " " . sprintf '%g%%', $c->{FundamentalData}{dividend}
                            if exists $c->{FundamentalData}{dividend};

                        $self->send_server( $SEND_CMD => $channel, $fun );
                    }

                    if ( $cmd eq 'q' || $cmd eq 'quote' ) {
                        my $company_name = $c->{name};
                        my $volume       = $c->{volume};
                        my $open         = $c->{open};
                        my $low          = $c->{low} || 0;
                        my $high         = $c->{high} || 0;
                        my $year_high    = sprintf '%g', $c->{FundamentalData}{yrhiprice} || 0;
                        my $year_low     = sprintf '%g', $c->{FundamentalData}{yrloprice} || 0;

                        my $yearly_range = $year_low . '-' . $year_high;
                        my $daily_range  = $low . '-'
                            . $high;            #$open > $last ? $open.'-'.$last : $last.'-'.$open;

                        my $quote =
                            "$name ($company_name) Last: $last $change_pretty $change_pct_pretty ";

                        if ( defined $volume && $volume ne '' && $volume gt 0 ) {
                            my $v = $self->format_units($volume);
                            $quote .= "(Vol: $v) ";
                        }

                        $quote .=
                              "Daily Range: ("
                            . $daily_range
                            . ") Yearly Range: ("
                            . $yearly_range . ")"
                            unless $yearly_range eq '0-0' && $daily_range eq '0-0';

                        my $curmktstatus = exists $c->{curmktstatus} ? $c->{curmktstatus} : '';

                        if ( $curmktstatus ne 'REG_MKT' && exists $c->{ExtendedMktQuote} ) {
                            if ( exists $c->{ExtendedMktQuote}{type}
                                && $c->{ExtendedMktQuote}{type} eq 'PRE_MKT' )
                            {
                                my $last = commify( $c->{ExtendedMktQuote}{last} );
                                my $v = $self->format_units( $c->{ExtendedMktQuote}{volume} );
                                my $change     = $c->{ExtendedMktQuote}{change};
                                my $change_pct = $c->{ExtendedMktQuote}{change_pct};
                                my $change_pretty =
                                    String::IRC->new( $change > 0 ? '+' . $change : $change );
                                my $change_pct_pretty = String::IRC->new(
                                    $change_pct > 0
                                    ? '+' . $change_pct . '%'
                                    : $change_pct . '%'
                                );

                                if ( $change > 0 ) {
                                    $change_pretty->light_green;
                                }
                                elsif ( $change < 0 ) {
                                    $change_pretty->red;
                                }
                                else {
                                    $change_pretty->pink;
                                }

                                if ( $change_pct > 0 ) {
                                    $change_pct_pretty->light_green;
                                }
                                elsif ( $change_pct < 0 ) {
                                    $change_pct_pretty->red;
                                }
                                else {
                                    $change_pct_pretty->pink;    # neutral
                                }
                                $quote .=
                                    " PreMarket $last $change_pretty $change_pct_pretty (Vol: $v)";
                            }
                        }

                        if ( $curmktstatus ne 'REG_MKT' && exists $c->{ExtendedMktQuote} ) {
                            if ( exists $c->{ExtendedMktQuote}{type}
                                && $c->{ExtendedMktQuote}{type} eq 'POST_MKT' )
                            {
                                my $last = commify( $c->{ExtendedMktQuote}{last} );
                                my $v = $self->format_units( $c->{ExtendedMktQuote}{volume} );
                                my $change     = $c->{ExtendedMktQuote}{change};
                                my $change_pct = $c->{ExtendedMktQuote}{change_pct};
                                my $change_pretty =
                                    String::IRC->new( $change > 0 ? '+' . $change : $change );
                                my $change_pct_pretty = String::IRC->new(
                                    $change_pct > 0
                                    ? '+' . $change_pct . '%'
                                    : $change_pct . '%'
                                );

                                if ( $change > 0 ) {
                                    $change_pretty->light_green;
                                }
                                elsif ( $change < 0 ) {
                                    $change_pretty->red;
                                }
                                else {
                                    $change_pretty->pink;
                                }

                                if ( $change_pct > 0 ) {
                                    $change_pct_pretty->light_green;
                                }
                                elsif ( $change_pct < 0 ) {
                                    $change_pct_pretty->red;
                                }
                                else {
                                    $change_pct_pretty->pink;    # neutral
                                }
                                $quote .=
                                    " PostMarket $last $change_pretty $change_pct_pretty (Vol: $v)";
                            }
                        }

                        $self->send_server( $SEND_CMD => $channel, $quote );
                    }

                }

                if ( $cmd ne 'q' && $cmd ne 'quote' && $cmd ne 'fun' ) {
                    $summary =~ s/\s+$//;
                    $self->send_server( $SEND_CMD => $channel, $summary )
                        if defined $summary && length $summary;
                }
            }
        );
    }
    catch($e) {
        warn $e;
        }

        return 1;
} ## ---------- end sub command_run

sub quote_fetch {


}


sub finances {
    my ( $self, $channel, $nick, $symbol, $long ) = @_;

    $long |= 0;

    my $url = sprintf ' http://finviz.com/quote.ashx?t=%s', $symbol;
    my $summary = '';

    try {
        $self->asyncsock->get(
            $url,
            sub {
                my ( $body, $header ) = @_;

                return unless defined $body && defined $header;

                my $title;
                my %f;
                my @k = ();
                my @v = ();

                my $p = undef;

                my $parser = HTML::TokeParser->new( \$body );

                $title = $parser->get_trimmed_text('/title');
                $title =~ s/Stock Quote //;
                warn "TITLE: $title";

                while ( my $token = $parser->get_tag('td') ) {
                    next unless ( defined $token->[1] && exists $token->[1]{'class'} );

                    my $c = $token->[1]{'class'};

                    if ( $c =~ 'snapshot-td2-cp' || $c =~ 'snapshot-td2' ) {
                        my $text = $parser->get_text("/td");
                        if ( defined $p ) {
                            warn "$p : $text";
                            $f{$p} = $text;
                            $p = undef;
                        }
                        else {
                            $p = $text;
                        }

                    }
                }

                my $len    = 0;
                my $keylen = 0;
                my $vallen = 0;
                my %fun;

                foreach my $key ( keys %f ) {

                    next
                        unless ( $long == 1
                        || $key =~
                        '^(Market Cap|Dividend|Dividend \%|Payout|Sales|Income|Book\/sh|Cash\/sh|P\/E|P\/C|EPS \(ttm\)|P\/FCF|Debt\/Eq|ROA|ROE|ROI|Shs Outstand|Beta|Perf YTD|ATR|Volatility|Volume|RSI \(14\)|52W Range)$'
                        );

                    my $val = $f{$key};
                    my $kl  = ( length $key ) + 1;
                    my $vl  = ( length $val ) + 1;
                    $keylen = $kl if $kl > $keylen;
                    $vallen = $vl if $vl > $vallen;

                    $fun{$key} = $val;
                    warn "$key $val";
                }

                return unless ( scalar keys %fun ) > 4;

                my $level = 0;
                my $summary;

                my $title_pretty = "[" . String::IRC->new("$nick")->purple . "]";
                $title_pretty .= " $title ";
                $title_pretty .= String::IRC->new( $f{Price} )->bold;

                $self->send_server( $SEND_CMD => $channel, $title_pretty );

                foreach my $k ( keys %fun ) {

                    my $sum = sprintf( "%-" . $keylen . "s %-" . $vallen . "s", $k, $fun{$k} );

                    $summary .= $sum;
                    $level++;
                    if ( $level == 6 ) {

                        #warn $summary;
                        $self->send_server( $SEND_CMD => $long ? $nick : $channel, $summary );
                        $summary = '';
                        $level   = 0;
                    }
                }

            }
        );
    }
    catch($e) {
        warn("An error occured while finances() was executing: $e");
    };
} ## ---------- end sub finances

sub stock_book {

    my ( $self, $channel, $symbol ) = @_;

    return unless defined $symbol;

    my $url = sprintf 'http://www.batstrading.com/json/edgx/book/%s', $symbol;

    try {
        $self->asyncsock->get(
            $url,
            sub {
                my ( $body, $header ) = @_;

                return unless defined $body && defined $header;

                my $json_object = $body;
                my $j           = $self->_jsonify($json_object);
                my $json        = $j->{data};

                return
                       unless defined $json
                    && exists $json->{company}
                    && length $json->{company}
                    && exists $json->{last}
                    && exists $json->{change}
                    && exists $json->{orders}
                    && exists $json->{asks}
                    && exists $json->{bids}
                    && exists $json->{high}
                    && exists $json->{volume};

                # warn Dumper($json);

                my $name   = $json->{company};
                my $symbol = $json->{symbol};
                my $last   = commify( $json->{last} );
                my $change = sprintf "%.3f", $json->{change};
                my $orders = commify( $json->{orders} );
                my $volume = commify( $json->{volume} );
                my $open   = sprintf "%.3f", $json->{open};
                my $low    = sprintf "%.3f", $json->{low};
                my $high   = sprintf "%.3f", $json->{high};
                my $prev   = sprintf "%.3f", $json->{prev};
                my $asks   = $json->{asks};
                my $bids   = $json->{bids};

                my $change_pretty = String::IRC->new($change)->pink;

                $change_pretty->light_green if substr( $change, 1, 1 ) eq '+';

                my $quote =
                    "$symbol ($name) Last: $last ($change_pretty) Orders: $orders Volume: $volume Open: $open High: $high Low: $low Prev: $prev ";

                $self->send_server( $SEND_CMD => $channel, $quote );

                return 1;

            }
        );
    }
    catch($e) {
        warn("An error occured while currency_convert was executing: $e");
    };

} ## ---------- end sub stock_book

sub currency_convert {
    my ( $self, $channel, $begin, $dst, $amount ) = @_;

    return
           unless defined $begin
        && length $begin
        && defined $dst
        && length $dst
        && defined $amount
        && length $amount;

    my $url = sprintf 'http://www.xe.com/currencyconverter/convert/?Amount=%s&From=%s&To=%s',
        $amount, $begin, $dst;

    my $summary = '';

    try {
        $self->asyncsock->get(
            $url,
            sub {
                my ( $body, $header ) = @_;

                return unless defined $body && defined $header;

                my $parser = HTML::TokeParser->new( \$body );
                while ( my $token = $parser->get_tag('tr') ) {
                    next unless ( defined $token->[1] && exists $token->[1]{'class'} );

                    my $c = $token->[1]{'class'};

                    if ( $c =~ 'uccRes' ) {
                        my $text = $parser->get_trimmed_text("/tr");
                        $text =~ s/^\s+//;
                        $text =~ s/([^[:ascii:]]+)/unidecode($1)/ge;

                        return unless defined $text && length $text;

                        my ( $asset_a,  $asset_b )    = split( / = /, $text );
                        my ( $amount_a, $currency_a ) = split( / /,   $asset_a );
                        my ( $amount_b, $currency_b ) = split( / /,   $asset_b );

                        # warn "Raw result: [$text]";

                        $amount_a =~ s/^\s+//;
                        $amount_a =~ s/^\s+//;
                        $amount_b =~ s/\s+$//;
                        $amount_b =~ s/\s+$//;

                        return
                               unless defined $amount_a
                            && length $amount_a
                            && $amount_a > 0
                            && defined $amount_b
                            && length $amount_b
                            && $amount_b > 0;

                        return
                               unless defined $currency_a
                            && defined $currency_b
                            && length $currency_a
                            && length $currency_b;

                        $summary = '';
                        $summary .= String::IRC->new($amount_a)->light_green;
                        $summary .= ' ' . $currency_a . ' = ';
                        $summary .= String::IRC->new($amount_b)->light_green;
                        $summary .= ' ' . $currency_b;

                        $self->send_server( $SEND_CMD => $channel, $summary );

                        return 1;
                    }
                }

            }
        );
    }
    catch($e) {
        warn("An error occured while currency_convert was executing: $e");
    };
} ## ---------- end sub currency_convert

sub market_movers {
    my $self    = shift;
    my $channel = shift;
    my $market  = shift || $mktmovers_sp500;

    try {

        $self->asyncsock->post(
            'http://api.cnbc.com/api/movers/common/lib/asp/bufferGainersLosers.asp',
            [
                'data'            => $market,
                '..requester..'   => 'ContentBuffer',
                '..contenttype..' => 'text/javascript',
            ],
            sub {
                my ( $body, $header ) = @_;

                return unless defined $body && defined $header;

                my $json_object = $body;
                $json_object =~ s/this\.marketData \=//g;
                my $json = $self->_jsonify($json_object);
                my $summary;

                for my $x ( @{ $json->{gainers} } ) {
                    my $change_pretty =
                        String::IRC->new( '+' . $x->{change} . '%' )->light_green;
                    my $company = $x->{company};
                    my $ticker  = $x->{ticker};
                    $summary .= "$ticker($company) $change_pretty  ";
                }

                if ( length $summary ) {
                    $self->send_server( $SEND_CMD => $channel, "Gainers - $summary" );
                }

                $summary = '';

                for my $y ( @{ $json->{losers} } ) {
                    my $change_pretty = String::IRC->new( '-' . $y->{change} . '%' )->red;
                    my $company       = $y->{company};
                    my $ticker        = $y->{ticker};
                    $summary .= "$ticker($company) $change_pretty  ";
                }

                if ( length $summary ) {
                    $self->send_server( $SEND_CMD => $channel, "Losers - $summary" );
                }

            }
        );
    }
    catch($e) {
        warn $e;
        }

        return 1;
} ## ---------- end sub market_movers

sub news_search {
    my ( $self, $channel, $nick, $symbol ) = @_;

    return unless defined $symbol;

    warn "* News search for $symbol\n";

    my $query =
          'select * from feed where url=\'http://feeds.finance.yahoo.com/rss/2.0/headline?s='
        . $symbol
        . '&f=sl1d1t1c1ohgv&e=.csv\'';
    my $params =
        "format=json&diagnostics=true&env=store%3A%2F%2Fdatatables.org%2Falltableswithkeys&callback=";
    my $url = sprintf 'http://query.yahooapis.com/v1/public/yql?q=%s&%s', uri_escape($query),
        $params;

    warn $url;

    try {
        $self->asyncsock->get(
            $url,
            sub {
                my ( $body, $header ) = @_;

                return unless defined $body && defined $header;

                my $json_object = $body;
                my $j           = $self->_jsonify($json_object);
                my $results     = $j->{query}{results}{item};

                #warn $body;
                #warn Dumper($results);

                return unless defined $results;

                my $idx = 5;
                foreach my $x ( @{$results} ) {
                    my $title = $x->{title};
                    my $link  = $x->{link};

                    next
                        unless defined $title && defined $link && length $title && length $link;

                    my $title_pretty = "[" . String::IRC->new("$symbol")->purple . "]";
                    my ( $short, $fetch_title ) = $self->{Owner}->_shorten( $link, 0 );
                    $self->send_server(
                        $SEND_CMD => $channel,
                        "$title_pretty $title - $short"
                    );                          # - $fetch_title" );
                    $idx--;

                    last if $idx <= 0;

                    #warn Dumper($x);
                }

                return 1;

            }
        );
    }
    catch($e) {
        warn("An error occured while news_search was executing: $e");
    };
} ## ---------- end sub news_search

sub quoteminimal {
    my ( $self, $channel, $nick, $symbol ) = @_;

    #return unless defined $symbols;

    #my $symbol = '';
    #$symbol .= '"$val",' foreach my $val (@symbols);

    #my $symbolString = join(',', $symbol);

    for my $k (@{$symbol}) {
        warn $k;
    }

    #warn Dumper $symbol;;
    #warn "Symbol string: $symbol\n";

    #my $query = 'select * from yahoo.finance.historicaldata where symbol = "YHOO" and startDate = "2009-09-11" and endDate = "2009-09-11"';
    my $params =
        "format=json&diagnostics=true&env=store%3A%2F%2Fdatatables.org%2Falltableswithkeys&callback=";
    my $query =
        sprintf 'select * from yahoo.finance.quote where symbol in ("SPY","CLK15.NYM","AAPL")';
    my $url = sprintf "http://query.yahooapis.com/v1/public/yql?q=%s&%s", uri_escape($query),
        $params;

    try {
        $self->asyncsock->get(
            $url,
            sub {
                my ( $body, $header ) = @_;

                return unless defined $body && defined $header;

                my $json_object = $body;
                my $j           = $self->_jsonify($json_object);

                my $results;
                if ( !exists $j->{query}{results}{quote} ) {

                    # retry
                }

                $results = $j->{query}{results}{quote};

                #warn Dumper($j);                #$results);

                return 1;

            }
        );
    }
    catch($e) {
        warn("An error occured while quoteminimal was executing: $e");
    };
} ## ---------- end sub quoteminimal

sub format_units {
    my $self  = shift;
    my $value = shift;
    my $ret;

    if ( $value > 1000000 ) {
        my $n = $value / 1000000;
        $ret = sprintf '%.2fM', $n;
    }
    elsif ( $value < 1000000 && $value > 1000 ) {
        my $n = $value / 1000;
        $ret = sprintf '%.2fK', $n;
    }
    else {
        $ret = $value;
    }

    return $ret;
} ## ---------- end sub format_units

sub _jsonify {
    my $self = shift;
    my $arg  = shift;
    my $hashref;
    try {
        $hashref = decode_json( encode( "utf8", $arg ) );
    }
    catch($e) {
        $hashref = undef;
    } return $hashref;
} ## ---------- end sub _jsonify

sub commify {
    local $_ = shift;
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

