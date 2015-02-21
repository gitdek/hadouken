package Hadouken::Plugin::Shredder;

use strict;
use warnings;

use Hadouken ':acl_modes';

use String::IRC;
use Encode qw( encode );
use JSON::XS qw( encode_json decode_json );

use Data::Printer alias => 'Dumper', colored => 1;

# use Data::Dumper;

use Hash::AsObject;

use TryCatch;

our $VERSION = '0.1';
our $AUTHOR  = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return
        "crypto quote eg ... btc or .ticker btc_usd ltc (btc ltc) or .ticker btc for multi exchanges";

} ## ---------- end sub command_comment

# Clean name of command.
sub command_name {
    my $self = shift;

    return "shredder";
}

sub command_regex {
    my $self = shift;

    return '(shredder|ticker|btc|\.\.\s.+?)';
}

# Return 1 if OK.
# 0 if does not pass ACL.
sub acl_check {
    my ( $self, %aclentry ) = @_;

    my $permissions = $aclentry{'permissions'};
    my $who         = $aclentry{'who'};
    my $channel     = $aclentry{'channel'};
    my $message     = $aclentry{'message'};

    # Or you can do it with the function Hadouken exports.
    # Make sure at least one of these flags is set.
    #if($self->check_acl_bit($permissions, Hadouken::BIT_ADMIN)
    #    || $self->check_acl_bit($permissions, Hadouken::BIT_WHITELIST)
    #    || $self->check_acl_bit($permissions, Hadouken::BIT_OP)) {

    #    return 1;
    #}

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

    if ( $cmd eq 'btc' ) {
        $cmd = '..';
        $arg = 'btc';
    }

    if ( $cmd eq 'ticker' ) {
        $arg = 'btc' unless defined $arg && length $arg;
    }

    warn "Shredder called with command: $cmd";

    return
        unless ( defined($arg) && length($arg) );

    if ( $cmd eq 'ticker' ) {
        my $ret = $self->do_ticker( $arg, $channel );
        return $ret;
    }

    my @coins = split( / /, $arg );

    foreach my $coin (@coins) {
        my ( $first_symbol, $second_symbol ) = split /[_\/]+/, $coin;
        $second_symbol ||= 'usd';
        my $ticker_url =
              'http://marketstem.com/api/aggregate/ticker?markets='
            . $first_symbol . '_'
            . $second_symbol;

        $self->asyncsock->get(
            $ticker_url,
            sub {
                my ( $body, $header ) = @_;
                my $json = $self->_jsonify($body);
                my $item = $json->[0];

                #my $obj= Hash::AsObject->new($json->[0]);

                my $totalVolume     = $item->{'totalVolume'};
                my $exchangeVolumes = $item->{'exchangeVolumes'};
                my $prettyVolumes   = '';

                my @keys =
                    sort { $exchangeVolumes->{$a} <=> $exchangeVolumes->{$b} }
                    keys(%$exchangeVolumes);
                foreach my $k ( reverse @keys ) {

                    #foreach my $k (keys %{$exchangeVolumes}) {
                    my $v = $exchangeVolumes->{$k};
                    warn $k . " - " . $v;

                    my $p = ( $v * 100 ) / $totalVolume;

                    my $pp = sprintf "%.4f%%", abs($p);

                    my $k = lc($k);
                    $k =~ s/(\w+)/\u$1/g;

                    $prettyVolumes .= " (" . $k . ": $v)";
                }

                my $id = $item->{'market'};
                my ( $asset_a, $asset_b ) = split( /\_/, uc($id) );

                my $last   = $item->{'vwaLast'};
                my $last15 = $item->{'vwaLast15'};

                my $price_15m_difference = ( ( $last - $last15 ) / $last15 ) * 100;
                my $prelabel = $price_15m_difference >= 0 ? '+' : '-';
                my $pretty_pchange = String::IRC->new( sprintf "%s%.3f%%",
                    $prelabel, abs($price_15m_difference) );

                warn $price_15m_difference;
                warn $last;

                if ( $price_15m_difference > 0 ) {
                    $pretty_pchange->light_green;
                }
                elsif ( $price_15m_difference < 0 ) {
                    $pretty_pchange->red;
                }
                else {
                    $pretty_pchange->grey;
                }

                my $pretty_price = String::IRC->new($last);

                my $summary =
                      $asset_a . " ("
                    . $id
                    . ") Last: "
                    . $last . " "
                    . $pretty_pchange
                    . " Vol: "
                    . $totalVolume
                    . "";                       # Daily Range: (".$price_before_24h."-".$price.") ";
                $summary .= $prettyVolumes;

                #$summary .= "(Vol: ".$volume_btc." btc) " if(lc($asset_a) ne 'btc');
                #$summary .= " Exchange: $best_market";
                $self->send_server( PRIVMSG => $channel, $summary );

                #if($id eq 'BTC_USD' && $last > 0 && $last < 350) {
                #    $self->send_server(PRIVMSG => $channel,'(╯°□°）╯︵ ┻━┻');
                #}
                #print Dumper($exchangeVolumes);
                # my $totalVolume = $json{'totalVolume'};

                #for my $item ( @{$json}) {
                #    print Dumper($item);

                #my $totalVolume = $item{totalVolume};
                #my $exchangeVolumes = $item{exchangeVolumes};

                #warn Dumper($exchangeVolumes);
                #}

            }
        );
    }

    return 1;
} ## ---------- end sub command_run

sub do_ticker {
    my ( $self, $arg, $channel ) = @_;          #= shift;

    my @coins     = split( / /, $arg );
    my $processed = 0;
    my $proc_line = 0;
    my @exchanges = (
        "ANXPRO",   "BITFINEX", "BITSTAMP",  "BITTREX",
        "BTCCHINA", "BTCE",     "BTER",      "CAMPBX",
        "CEXIO",    "COINBASE", "CRYPTONIT", "CRYPTSY",
        "HITBTC",   "ITBIT",    "KRAKEN",    "LAKEBTC",
        "POLONIEX", "VAULTOFSATOSHI"
    );
    my $ASSET = '';

    foreach my $c (@coins) {
        my ( $first_symbol, $second_symbol ) = split /[_\/\\]+/, $c;
        $second_symbol ||= 'usd';
        $ASSET .= uc($first_symbol) . "_" . uc($second_symbol) . ",";
    }

    $ASSET = substr( $ASSET, 0, -1 );

    my %summaries;

    foreach my $exchange (@exchanges) {
        my $url = "http://marketstem.com/api/" . $exchange . "/ticker?markets=" . $ASSET;

        $self->asyncsock->get(
            $url,
            sub {
                my ( $body, $header ) = @_;
                my $json = $self->_jsonify($body);

                for my $c (@$json) {

                    next
                        unless defined $c
                        && exists $c->{last}
                        && exists $c->{market}
                        && exists $c->{exchange};

                    my $price = sprintf( "%f", $c->{last} );

                    next unless defined $price && length $price && $price > 0;

                    my $market   = $c->{market};
                    my $exchange = $c->{exchange};
                    $exchange = lc($exchange);
                    $exchange =~ s/(\w+)/\u$1/g;
                    $summaries{$market}{$exchange} = $price;
                }

                return unless scalar( keys %summaries ) > 0;

                $processed++;
                $proc_line++;

                if ( $processed >= scalar(@exchanges) || $proc_line >= 8 ) {
                    $proc_line = 0;

                    #my $out = "Last: ";
                    #$out .= join(' ', @crap);
                    #$self->send_server (PRIVMSG => $channel, $out);
                    #@crap = ();

                    keys %summaries;
                    while ( my ( $k, $v ) = each %summaries ) {

                        #warn "key: $k value: $v\n";
                        keys %{$v};
                        my $crap = "$k ";
                        while ( my ( $x, $y ) = each %{$v} ) {
                            my $exchange_name = String::IRC->new($x)->cyan;    #->bold;
                            $crap .= "($exchange_name $y) ";
                            delete $summaries{$k}{$x};    # This is safe here.
                        }
                        warn $crap;

                        $self->send_server( PRIVMSG => $channel, $crap );

                        delete $summaries{$k};
                    }
                }
            }
        );
    }

    return 0;

} ## ---------- end sub do_ticker

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

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Hadouken::Plugin::Ticker - Crypto-currency ticker plugin.

=head1 DESCRIPTION

Crypto ticker plugin for Hadouken.

=head1 AUTHOR

dek - L<http://dek.codes/>

=cut

