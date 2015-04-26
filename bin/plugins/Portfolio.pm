package Hadouken::Plugin::Portfolio;
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

# use Data::Dumper;
use Data::Printer alias => 'Dumper', colored => 1;

our $VERSION = '0.1';
our $AUTHOR  = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    my $ret = '';
    $ret .= "Financial Portfolio commands:\n";
    $ret .=
        "  portfolio add [symbol] [shares] [optional:price] - If price is left empty, uses current. Shares can be negative for short position.\n";
    $ret .= "  portfolio remove [symbol]\n";
    $ret .= "  portfolio link - Get a link to a pretty chart of your portfolio.\n";

    return $ret;
} ## ---------- end sub command_comment

# Clean name of command.
sub command_name {
    my $self = shift;

    return "portfolio";
}

sub command_regex {
    my $self = shift;

    # portfolio add <symbol> <shares> <optional:price> - if price is empty, adds current price.
    # portfolio remove <symbol>
    #
    return 'portfolio(\sadd\s.+?|\sremove\s.+?|\ssummary)$';
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

    #if ( $channel eq '#stocks' || $channel eq '#trading' ) {
    #    return 0;
    #}

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
    my ( $cmd, $subcmd, $arg ) = split( / /, lc($message), 3 );

    warn "Command: $cmd";
    warn "Sub-command: $subcmd";

    warn "Arguments:" . ( defined $arg ? $arg : "None" );

    $self->_load_portfolio() unless $self->{_portfolio_initialized} == 1;

    if ( lc $subcmd eq 'add' ) {
        $self->_portfolio_add( $channel, $nick, split( / /, $arg ) );
    }
    elsif ( lc $subcmd eq 'summary' ) {
        $self->_portfolio_summary( $nick, $channel );
    }

    return 1;
} ## ---------- end sub command_run

sub _portfolio_add {
    my ( $self, $channel, $nick, $symbol, $shares, $price ) = @_;

    return unless defined $shares && $shares ne '0';

    if ( !defined $price || $price le '0' ) {

        my $open_price = $self->price_lookup($symbol);

        warn "Returned price: $open_price";

        return unless defined $open_price && $open_price ne 0;

        $price = $open_price;

        # Lookup price here.
        #$price = '100';
    }

    #if ( !exists $self->{_portfolio}{$nick}{$symbol} ) {

    my $key = "$symbol-" . time();

    $self->{_portfolio}{$nick}{$key}{shares}   = $shares;
    $self->{_portfolio}{$nick}{$key}{price}    = $price;
    $self->{_portfolio}{$nick}{$key}{buy_cost} = $price * $shares;
    $self->{_portfolio}{$nick}{$key}{holdings} = $price * $shares;
    $self->{_portfolio}{$nick}{$key}{date}     = time();

    $self->send_server( PRIVMSG => $channel, "Added $shares shares of $symbol at $price." );

    #}# else {

    #  if($shares < 0) {

    #   }

    #}

    # Then update the entire users portfolio earnings;

    my %portfolio = %{ $self->{_portfolio} };

    warn "Dumping portfolio:";
    warn Dumper(%portfolio);

    $self->_update_portfolio($nick);

} ## ---------- end sub _portfolio_add

sub _update_portfolio {

    my ( $self, $nick ) = @_;

    return unless defined $nick;

    my $total_holdings = 0;
    my $total_buy_cost = 0;
    my $total_pl       = 0;

    foreach my $symbol ( keys %{ $self->{_portfolio}{$nick} } ) {
        next if $symbol eq 'summary';

        my ( $actual_symbol, $symbol_epoch ) = split( /-/, $symbol );
        my $open_price = $self->price_lookup($actual_symbol);
        my $s          = $self->{_portfolio}{$nick}{$symbol}{shares};
        my $p          = $self->{_portfolio}{$nick}{$symbol}{price};

        my $h;
        my $bc;

        if ( $s lt 0 ) {
            $h  = ( $s * -1 ) * $open_price;
            $bc = ( $s * -1 ) * $p;
        }
        else {
            $h  = $open_price * $s;
            $bc = $s * $p;
        }

        $self->{_portfolio}{$nick}{$symbol}{buy_cost} = $bc;
        $self->{_portfolio}{$nick}{$symbol}{holdings} = $h;

        my $pl = $s < 0 ? $bc - $h : $h - $bc;

        $self->{_portfolio}{$nick}{$symbol}{pl} = $pl;

        $total_holdings += $h;
        $total_buy_cost += $bc;                 #$self->{_portfolio}{$nick}{$symbol}{buy_cost};

        $total_pl += $pl;

        #warn "KEY: $key";

    }

    $self->{_portfolio}{$nick}{summary}{total_pl}       = $total_pl;
    $self->{_portfolio}{$nick}{summary}{total_holdings} = $total_holdings;
    $self->{_portfolio}{$nick}{summary}{total_buy_cost} = $total_buy_cost;

    my $ct = ( $total_holdings - $total_buy_cost );

    #my $ct = $s < 0 ? $total_buy_cost - $total_holdings : $total_holdings - $total_buy_cost;

    $self->{_portfolio}{$nick}{summary}{change_total} = $ct;

    my $pct = ( ( $total_holdings - $total_buy_cost ) / $total_buy_cost ) * 100;

    $self->{_portfolio}{$nick}{summary}{change_percent} = abs($pct);

    warn Dumper( $self->{_portfolio} );

    $self->_save_portfolio();


} ## ---------- end sub _update_portfolio

sub _portfolio_summary {
    my ( $self, $nick, $channel ) = @_;

    return unless exists $self->{_portfolio}{$nick};

    foreach my $symbol ( keys %{ $self->{_portfolio}{$nick} } ) {
        next if $symbol eq 'summary';

        my ( $actual_symbol, $symbol_epoch ) = split( /-/, $symbol );

        my $shares   = $self->{_portfolio}{$nick}{$symbol}{shares};
        my $price    = $self->{_portfolio}{$nick}{$symbol}{price};
        my $holdings = $self->{_portfolio}{$nick}{$symbol}{holdings};
        my $buy_cost = $self->{_portfolio}{$nick}{$symbol}{buy_cost};
        my $pl       = $self->{_portfolio}{$nick}{$symbol}{pl};
        my $ppl      = $self->format_color($pl);

        #my $ppl = $pl > 0 ? String::IRC->new($pl)->light_green : String::IRC->new($pl)->red;

        my $header = sprintf "[%s] %s-%s", String::IRC->new($nick)->purple,
            String::IRC->new( uc $actual_symbol )->fuchsia, $symbol_epoch;
        my $line = sprintf "%s Shares: %s Price: %s Holdings: %s Buy Cost: %s P\/L: %s",
            $header, $self->format_units($shares), $price, $self->format_units($holdings),
            $self->format_units($buy_cost), $self->format_color($pl);

        warn $line;

        $self->send_server( PRIVMSG => $channel, $line );

    }

    my $th  = $self->{_portfolio}{$nick}{summary}{total_holdings};
    my $tbc = $self->{_portfolio}{$nick}{summary}{total_buy_cost};
    my $tpl = $self->{_portfolio}{$nick}{summary}{total_pl};
    my $tcp = sprintf '%.2f', $self->{_portfolio}{$nick}{summary}{change_percent};

    my $pct = '';

    if ( $tpl > 0 ) {
        $pct = String::IRC->new( '+' . $tcp . '%' )->light_green;
    }
    elsif ( $tpl < 0 ) {
        $pct = String::IRC->new( '-' . $tcp . '%' )->red;
    }
    else {
        $pct = String::IRC->new( '-' . $tcp . '%' )->grey;
    }

    #my $pct = sprintf $tpl > 0 ? '+%s%%' : '-%s%%', $self->{_portfolio}{$nick}{summary}{change_percent};

    my $total_summary = sprintf "[%s] Total holdings: %s Total buy cost %s P\/L: %s %s",
        String::IRC->new($nick)->purple, $self->format_units($th), $self->format_units($tbc), $self->format_color($tpl), $pct;

    $self->send_server( PRIVMSG => $channel, $total_summary );

    warn $total_summary;

    return 1;
} ## ---------- end sub _portfolio_summary

sub _save_portfolio {
    my ($self) = @_;

    return unless defined $self->{_portfolio};

    # $self->_calc_trivia_rankings;

    open( my $fh, ">" . $self->{Owner}->{ownerdir} . '/../data/portfolio.json' );
    my %portfolio = %{ $self->{_portfolio} };
    my $json_data = JSON->new->allow_nonref->encode( \%portfolio );
    print $fh $json_data;
    close($fh);

    return 1;
} ## ---------- end sub _save_portfolio

sub _load_portfolio {
    my ($self) = @_;

    warn "* Loading portfolio...";

    if ( -e $self->{Owner}->{ownerdir} . '/../data/portfolio.json' ) {
        open( my $fh, $self->{Owner}->{ownerdir} . '/../data/portfolio.json' ) or die $!;
        my $json_data;
        read( $fh, $json_data, -s $fh );        # Suck in the whole file
        close $fh;

        my $temp_portfolio = JSON->new->allow_nonref->decode($json_data);

        %{ $self->{_portfolio} } = %{$temp_portfolio};

        $self->{_portfolio_initialized} = 1;
    }

    return 1;
}

sub price_lookup {

    my ( $self, $symbol ) = @_;

    my $url =
        "http://quote.cnbc.com/quote-html-webservice/quote.htm?callback=webQuoteRequest&symbols=%s&symbolType=symbol&requestMethod=quick&exthrs=1&extMode=&fund=1&entitlement=0&skipcache=&extendedMask=1&partnerId=2&output=jsonp&noform=1";

    $url = sprintf "$url", "$symbol";

    my $open_price = undef;

    try {
        my $body = $self->{Owner}->_webclient->get($url)->decoded_content;

        my $json_object;

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

        # my $summary;
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

            warn "Last price: " . $c->{last};

            $open_price = $c->{last};

            last;

        }
    }
    catch($e) {

        warn $e;
        }

        return $open_price;
} ## ---------- end sub price_lookup

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

                        $self->send_server( PRIVMSG => $channel, $summary );

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

sub format_units {
    my $self  = shift;
    my $value = shift;
    my $ret;

    if ( $value >= 1000000 ) {
        my $n = $value / 1000000;
        $ret = sprintf '%.6gM', $n;
    }
    elsif ( $value <= 1000000 && $value >= 1000 ) {
        my $n = $value / 1000;
        $ret = sprintf '%.5gK', $n;
    }
    else {
        $ret = $value;
    }

    return $ret;
} ## ---------- end sub format_units

sub format_color {
    my $self = shift;
    my $value = shift || 0;

    my $ret = String::IRC->new($value);

    if ( $value > 0 ) {
        $ret->light_green;
    }
    elsif ( $value < 0 ) {
        $ret->red;
    }
    else {
        $ret->pink;
    }

    return $ret;
} ## ---------- end sub format_color

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Hadouken::Plugin::Portfolio - Financial Portfolio plugin.

=head1 DESCRIPTION

Financial Portfolio plugin for Hadouken.

=head1 AUTHOR

dek - L<http://dek.codes/>

=cut

