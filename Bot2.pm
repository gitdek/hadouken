package CashBot;

use strict;
use warnings;
use diagnostics;

our $VERSION = '0.1';

use Data::Dumper;
#use Data::Printer alias => 'Dumper',colored => 1;

use Cwd ();

use List::MoreUtils ();
use List::Util ();

use AnyEvent;
use AnyEvent::IRC::Client;
use AnyEvent::DNS;
use AnyEvent::IRC::Util ();

use HTML::TokeParser;
use URI ();
use LWP::UserAgent ();
use Encode qw( encode ); 
use JSON::XS qw( decode_json );
use POSIX qw(strftime);
use Time::HiRes qw( time sleep );
use Geo::IP;
use Tie::Array::CSV ();
use Regexp::Common;

use String::IRC;

use Moose;
# use Regexp::Grammars;
with qw(MooseX::Daemonize);


after start => sub {
   my $self = shift;
   return unless $self->is_daemon;

   $self->{connected} = 0;
   $self->{c} = AnyEvent->condvar;
   $self->{con} = AnyEvent::IRC::Client->new();

   $self->_start;
};

my $command_prefix = '^(!|\.)';

my @commands = (
      {name => 'ipcalc',   regex => 'ipcalc\s.+?',          cb => undef, delegate => undef, acl => undef, comment => 'calculate ip netmask' },
      {name => 'calc',     regex => 'calc\s.+?',            cb => undef, delegate => undef, acl => undef, comment => 'google calculator' },
      {name => 'ticker',   regex => 'ticker\s.+?',          cb => undef, delegate => undef, acl => undef, comment => 'look up coin(ltc,doge,nmc) or coin pair(ltc_usd,doge_ltc,nvc_btc)' },
      {name => 'geoip',    regex => 'geoip\s.+?',           cb => undef, delegate => undef, acl => undef, comment => 'geo ip lookup' },
      {name => 'lq',       regex => '(lq|lastquote)$',      cb => undef, delegate => undef, acl => undef, comment => 'get most recently added quote' },
      {name => 'aq',       regex => '(aq|addquote)\s.+?',   cb => undef, delegate => undef, acl => undef, comment => 'add a quote' },
      {name => 'dq',       regex => '(dq|delquote)\s.+?',   cb => undef, delegate => undef, acl => undef, comment => 'delete quote' },
      {name => 'fq',       regex => '(fq|findquote)\s.+?',  cb => undef, delegate => undef, acl => undef, comment => 'find a quote' },
      {name => 'rq',       regex => '(rq|randquote)$',      cb => undef, delegate => undef, acl => undef, comment => 'get a random quote' },
      {name => 'q',        regex => '(q|quote)\s.+?',       cb => undef, delegate => undef, acl => undef, comment => 'get a quote by index' },
      {name => 'btc',      regex => 'btc$',                 cb => undef, delegate => undef, acl => undef, comment => 'display btc ticker' },
      {name => 'ltc',      regex => 'ltc$',                 cb => undef, delegate => undef, acl => undef, comment => 'display ltc ticker' },
      {name => 'eur2usd',  regex => '(e2u|eur2usd)$',       cb => undef, delegate => undef, acl => undef, comment => 'display euro to usd ticker' },
      {name => 'commands', regex => '(commands|cmds)$',     cb => undef, delegate => undef, acl => undef, comment => 'display list of commands' },
);

sub new {
   my $class = shift;
   my $self = {@_};

   bless $self, $class;

   return $self;
}

sub chain {
   my $self = shift;

   $self->{chain} = 1;

   return $self;
}

sub _ {
   return new(__PACKAGE__, args => [@_]);
}

sub _prepare {
   my $self = shift;
   unshift @_, @{$self->{args}} if defined $self->{args} && @{$self->{args}};
   return @_;
}

sub range {
   my $self = shift;
   my ($start, $stop, $step) =
      @_ == 3 ? @_ : @_ == 2 ? @_ : (undef, @_, undef);

   return [] unless $stop;

   $start = 0 unless defined $start;

   return [$start .. $stop - 1] unless defined $step;

   my $test = ($start < $stop)
      ? sub { $start < $stop }
      : sub { $start > $stop };

   my $new_array = [];
   while ($test->()) {
      push @$new_array, $start;
      $start += $step;
   }
   return $new_array;
}

sub detect {
    my $self = shift;
    my ($list, $iterator, $context) = $self->_prepare(@_);

    return List::Util::first { $iterator->($_) } @$list;
}

sub value {
   my $self = shift;

   return wantarray ? @{$self->{args}} : $self->{args}->[0];
}

sub _finalize {
   my $self = shift;

   return
      $self->{chain} ? do { $self->{args} = [@_]; $self }
         : wantarray ? @_
         : $_[0];
}

sub wrap {
   my $self = shift;

   my ($function, $wrapper) = $self->_prepare(@_);

   return sub {
      $wrapper->($function, @_);
   };
}

sub bind {
   my $self = shift;

   my ($function, $object, @args) = $self->_prepare(@_);

   return sub {
      $function->($object, @args, @_);
   };
}

sub map {
   my $self = shift;
   my ($array, $cb, $context) = $self->_prepare(@_);

   $context = $array unless defined $context;

   my $index = 0;
   my $result = [map { $cb->($_, ++$index, $context) } @$array];

   return $self->_finalize($result);
}

sub toArray {&to_array}

sub to_array {
   my $self = shift;
   my ($list) = $self->_prepare(@_);

   return [values %$list] if ref $list eq 'HASH';

   return [$list] unless ref $list eq 'ARRAY';

   return [@$list];
}

sub each {
   my $self = shift;
   my ($array, $cb, $context) = $self->_prepare(@_);

   return unless defined $array;

   $context = $array unless defined $context;

   my $i = 0;

   foreach (@$array) {
      $cb->($_, $i, $context);
      $i++;
   }
}

sub pluck {
   my $self = shift;
   my ($list, $key) = $self->_prepare(@_);

   my $result = [];

   foreach (@$list) {
      push @$result, $_->{$key};
   }

   return $self->_finalize($result);
}

# Global rules are:
# 
# 
# If you are +o or +v, and not on the blacklist you return OK.
# if you are neither +o or +v, we check the whitelist.
#

sub global_acl {
   my $self = shift;
   my ($who, $message, $channel, $channel_list) = @_;
   my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

   if(exists $channel_list->{$nickname}) {

      return 0 if($self->blacklisted($who));

      if(/(o|v)$/ ~~ $channel_list->{$nickname}) {
         return 1;
      } else {
         if($self->whitelisted($who)) {
            return 1;
         }
      }
   }

   return 0;
}

sub blacklisted {
   my $self = shift;
   my ($who, $fromwhat) = @_;

   my $ret = 0;

   warn "* blacklisted called\n";

   return $ret;
}

sub whitelisted {
   my $self = shift;

   my $who = shift;

   my $ret = 0;


   return $ret;
}

sub add_func {
   my $self = shift;

   my %params = @_;

   foreach(@commands) {
      if ($_->{'name'} eq $params{name}) {
         $_->{delegate} = $params{delegate} if(defined $params{delegate});
         $_->{cb} = $params{cb} if (defined $params{cb});
         $_->{acl} = $params{acl} if (defined $params{acl});
         last;
      }
   }
}

sub jsonify {
   my $self = shift;

   my $hashref = decode_json( encode("utf8", shift) );

   return $hashref;
}

sub fetch_json {
   my $self = shift;
   my $url = shift;

   my $json;

   eval {
      my $request = HTTP::Request->new('GET', $url);
      my $response = $self->_webclient->request($request);
      $json = $self->jsonify($response->content);
   };

   if($@) {
      warn "Error: $@\n";
   }

   return $json;
}

sub get_commands {
   my $self = shift;

   return _->map(\@commands, sub { my ($h) = @_; $h; });
}

sub _buildup {
   my $self = shift;

   $self->{quotesdb} = ();

   #my $redis = Redis->new;

   $self->{geoip} = Geo::IP->open(Cwd::abs_path('geoip/GeoIPCity.dat')) or die $!;

   my $tieobj = tie @{$self->{quotesdb}}, 'Tie::Array::CSV', 'quotes.txt', memory => 20_000_000 or die $!;

   #my $tieobj = tie @{$self->{adminsdb}}, 'Tie::Array::CSV', 'admins.db', memory => 20_000_000 or die $!;


   $self->add_func(name => 'ipcalc',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my ($cmd, $arg) = split(/ /, lc($message), 2);

         my ($network, $netbit) = split(/\//, $arg);

         return 
            unless 
               (defined($network)) && 
               (defined($netbit)) && 
               ($network =~ /$RE{net}{IPv4}/) &&
               ($netbit =~ /^$RE{num}{int}$/) && 
               ($netbit <= 32) && 
               ($netbit >= 0);


         my $res_calc = $self->calc_netmask($network."\/".$netbit);

         my $res_usable = $self->cidr2usable_v4($netbit);

         return unless (defined $res_calc) || (defined $res_usable);

         my $out_msg = "[ipcalc] $arg -> netmask: $res_calc - usable addresses: $res_usable";

         $self->{con}->send_srv (PRIVMSG => $channel, $out_msg);

         return 1;
    },
      acl => sub {
      
         return 1;
   });

   $self->add_func(name => 'calc',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my ($cmd, $arg) = split(/ /, lc($message), 2);

         return unless (defined($arg) && length($arg));

         my $res_calc = $self->calc($arg);

         return unless defined $res_calc;

         $self->{con}->send_srv (PRIVMSG => $channel, "[calc] $res_calc");

         return 1;
    },
      acl => sub {
      
         return 1;
   });

   $self->add_func(name => 'ticker',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my ($cmd, $arg) = split(/ /, lc($message), 2);

         return unless (defined($arg) && length($arg));

         my ($first_symbol, $second_symbol) = split(/_/,$arg,2);

         $second_symbol ||= 'usd';

         my $json = $self->fetch_json('http://www.cryptocoincharts.info/v2/api/tradingPair/'.$first_symbol.'_'.$second_symbol);

         return
            unless (
               (defined $json) && 
               (exists $json->{'id'}) && 
               (exists $json->{'price'}) && 
               (exists $json->{'volume_first'}) &&
               (grep { defined $_ && $_ ne '' } values $json));

         my $si = String::IRC->new($arg)->bold;
         my $ret =  "[$si] Id: $json->{id} Last: $json->{price} Volume: $json->{volume_first} Most volume: $json->{best_market}";

         $self->{con}->send_srv (PRIVMSG => $channel, $ret);

         return 1;
   },
      acl => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my $ret = $self->global_acl($who, $message, $channel, $channel_list);

         # add in some other behavior here if needed.
         return $ret;
   });

   $self->add_func(name => 'geoip',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my ($cmd, $arg) = split(/ /,$message, 2);

         # my $dns_cb = _->map(\@commands, sub { my ($h) = @_; return $h if($h->{name} eq 'geoip'); } );

         if( $arg =~ /$RE{net}{IPv4}/ ) {

            my $record = $self->{geoip}->record_by_addr( $arg );   

            return unless defined $record;

            my $ip_result = "$arg -> ";
            $ip_result .= " City:".$record->city if defined $record->city && $record->city ne '';
            $ip_result .= " Region:".$record->region if defined $record->region && $record->region ne '';
            $ip_result .= " Country:".$record->country_code if defined $record->country_code && $record->country_code ne '';

            $self->{con}->send_srv (PRIVMSG => $channel, $ip_result);           

         } elsif ( $arg =~ m{($RE{URI})}gos ) {

            my $uri = URI->new($arg);
            my $host_only = $uri->host;

            AnyEvent::DNS::resolver->resolve ($host_only, "a",
               sub {

                  # array = "banana.com", "a", "in", 3290, "113.10.144.102"
                  my $row = List::MoreUtils::last_value { grep { $_ eq "a" } @$_  } @_;

                  return unless (defined $row) || (@$row[4] =~ /$RE{net}{IPv4}/);

                  my $ip_addr = @$row[4];

                  return unless ($ip_addr =~ /$RE{net}{IPv4}/);

                  my $record = $self->{geoip}->record_by_addr($ip_addr);   

                  unless(defined $record) {
                     $self->{con}->send_srv (PRIVMSG => $channel, "$arg ($ip_addr) -> no results in db");
                     return;
                  }

                  my $dom_result = "$arg ($ip_addr) ->";
                  $dom_result .= " City:".$record->city if defined $record->city && $record->city ne '';
                  $dom_result .= " Region:".$record->region if defined $record->region && $record->region ne '';
                  $dom_result .= " Country:".$record->country_code if defined $record->country_code && $record->country_code ne '';

                  $self->{con}->send_srv (PRIVMSG => $channel, $dom_result);           
               } 
            );
         } else {

            # maybe implement by nick (in channel)
            # .geoip dek
            # if(exists $channel_list->{$nickname}) {
            # then do the lookup.
         }

         return 1;
    },
      acl => sub {
      
         return 1;
   },
      cb => sub {
         my $self = shift;

         return 1;
   });



   $self->add_func(name => 'fq',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my $quote_count = scalar @{$self->{quotesdb}};

         return unless $quote_count > 0;


         my ($cmd, $arg) = split(/ /,$message, 2);

         my $blah = $arg;

         $blah =~ s/^\s+//;
         $blah =~ s/\s+$//;

         return unless length($blah);

         #if($arg =~ 'creator:')
         #(?:^creator+$)

         my @found = grep { lc($_->[1]) =~ lc($arg) } @{$self->{quotesdb}};

         my $found_count = scalar @found;

         unless($found_count > 0) {
            $self->{con}->send_srv (PRIVMSG => $channel, 'nothing found in quotes!');
            return;
         }

         my $si = String::IRC->new($found_count)->bold;

         $self->{con}->send_srv (PRIVMSG => $channel, 'found '.$si.' quotes!');


         # my @test = [$ident, $arg, $channel, time()];


         return 1;
    },
      acl => sub {
      
         return 1;
   });

   $self->add_func(name => 'rq',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my $quote_count = scalar @{$self->{quotesdb}};

         if ($quote_count > 0) {

            my $rand_idx = int rand($quote_count);

            my @rand_quote = $self->{quotesdb}[$rand_idx];

            my ($q_mode_map,$q_nickname,$q_ident) = $self->{con}->split_nick_mode($rand_quote[0][0]);

            my $epoch_string = strftime "%a %b%e %H:%M:%S %Y", localtime($rand_quote[0][3]);

            my $si = String::IRC->new($rand_idx)->bold;

            $self->{con}->send_srv (PRIVMSG => $channel, '['.$si.'/'.$quote_count.'] '.$rand_quote[0][1].' - added by '.$q_nickname.' on '.$epoch_string);
         }

         return 1;
    },
      acl => sub {
      
         return 1;
   });

   $self->add_func(name => 'lq',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my $quote_count = scalar @{$self->{quotesdb}};

         if ($quote_count > 0) {

            my @last_quote = $self->{quotesdb}[int($quote_count - 1)];

            my ($q_mode_map,$q_nickname,$q_ident) = $self->{con}->split_nick_mode($last_quote[0][0]);

            my $epoch_string = strftime "%a %b%e %H:%M:%S %Y", localtime($last_quote[0][3]);

            $self->{con}->send_srv (PRIVMSG => $channel, '['.$quote_count.'] '.$last_quote[0][1].' - added by '.$q_nickname.' on '.$epoch_string);
         }

         return 1;
    },
      acl => sub {
      
         return 1;
   });

   $self->add_func(name => 'aq',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my ($cmd, $arg) = split(/ /,$message, 2);

         return unless (defined $arg) && (length $arg);

         my @test = [$ident, $arg, $channel, time()];

         push($self->{quotesdb}, @test);

         my $quote_count = scalar @{$self->{quotesdb}};

         $self->{con}->send_srv (PRIVMSG => $channel, 'Quote #'.$quote_count.' added by '.$nickname.'.');

         return 1;
    },
      acl => sub {
      
         return 1;
   });

   $self->add_func(name => 'commands',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         #my $cmd_names = _->pluck(\@commands, 'name');

         $self->{con}->send_srv (PRIVMSG => $channel, 'Commands:');

         my @copy = @commands;

         my $iter = List::MoreUtils::natatime 2, @copy;

         while( my @tmp = $iter->() ){

            my $command_summary = '';

            foreach my $c (@tmp) {
               my $si = String::IRC->new($c->{name})->bold;
               $command_summary .= '['.$si.'] -> '.$c->{comment}."  ";
            }

            #warn $command_summary,"\n\n";
            $self->{con}->send_srv (PRIVMSG => $channel, $command_summary);
            $command_summary = '';
         }

         return 1;
    },
      acl => sub {
      
         return 1;
   });

   # list coins
   
   # http://www.cryptocoincharts.info/v2/api/listCoins


   $self->add_func(name => 'btc', 
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my $json = $self->fetch_json('https://btc-e.com/api/3/ticker/btc_usd');
         my $json2 = $self->fetch_json('https://crypto-trade.com/api/1/ticker/btc_usd');

         my $ret =  "[btc_usd\@btce] Last: $json->{btc_usd}->{last} Low: $json->{btc_usd}->{low} High: $json->{btc_usd}->{high} Avg: $json->{btc_usd}->{avg} Vol: $json->{btc_usd}->{vol}";
         my $ret2 = "[btc_usd\@ct]   Last: $json2->{data}->{last} Low: $json2->{data}->{low} High: $json2->{data}->{high} Vol(usd): $json2->{data}->{vol_usd}";

         $self->{con}->send_srv (PRIVMSG => $channel, $ret);

         $self->{con}->send_srv (PRIVMSG => $channel, $ret2);

         return 1;
   },
      acl => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my $ret = $self->global_acl($who, $message, $channel, $channel_list);

         # add in some other behavior here if needed.

         return $ret;
   });

   $self->add_func(name => 'ltc', 
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my $json = $self->fetch_json('https://btc-e.com/api/3/ticker/ltc_usd');

         my $json2 = $self->fetch_json('https://crypto-trade.com/api/1/ticker/ltc_usd');

         #print Dumper($json),"\n";

         my $ret =  "[ltc_usd\@btce] Last: $json->{ltc_usd}->{last} Low: $json->{ltc_usd}->{low} High: $json->{ltc_usd}->{high} Avg: $json->{ltc_usd}->{avg} Vol: $json->{ltc_usd}->{vol}";
         
         my $ret2 = "[ltc_usd\@ct]   Last: $json2->{data}->{last} Low: $json2->{data}->{low} High: $json2->{data}->{high} Vol(usd): $json2->{data}->{vol_usd}";

         $self->{con}->send_srv (PRIVMSG => $channel, $ret);

         $self->{con}->send_srv (PRIVMSG => $channel, $ret2);

         return 1;
   },
      acl => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my $ret = $self->global_acl($who, $message, $channel, $channel_list);

         # add in some other behavior here if needed.

         return $ret;
   }, 
      cb => sub {

         return 1;
   });


   $self->add_func(name => 'eur2usd', 
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my $json = $self->fetch_json('https://btc-e.com/api/3/ticker/eur_usd');

         my $ret = "[eur_usd] Last: $json->{eur_usd}->{last} Low: $json->{eur_usd}->{low} High: $json->{eur_usd}->{high} Avg: $json->{eur_usd}->{avg} Vol: $json->{eur_usd}->{vol}";

         $self->{con}->send_srv (PRIVMSG => $channel, $ret);

         return 1;
   },
      acl => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my $ret = $self->global_acl($who, $message, $channel, $channel_list);

         # add in some other behavior here if needed.

         return $ret;
   });

   $self->{con}->reg_cb (
      connect => sub {
         my ($con, $err) = @_;
         if (defined $err) {
            warn "* Couldn't connect to server: $err\n";
         }
      },
      registered => sub {

         warn "* Registered!\n";
         
         $self->{connected} = 1;

         # in AnyEvent::IRC::Client, the function enable_ping sends "PING" => "AnyEvent::IRC". Lamers.
         #$self->{con}->enable_ping (60, sub {
         #   my ($con) = @_;

         #   warn "No PONG was received from server in 60 seconds\n";

         #   return;
         #});
      },
      disconnect => sub {

         warn "* Disconnected\n";

         $self->{connected} = 0;

         $self->{c}->broadcast;
      },
      kick => sub {
         my($con, $kicked_nick, $channel, $is_myself, $msg, $kicker_nick) = (@_);

         warn "* KICK CALLED -> $kicked_nick by $kicker_nick from $channel with message $msg -> is myself: $is_myself!\n";

         warn "my nick is ". $self->{con}->nick() ."\n";

         if($self->{con}->nick() eq $kicked_nick || $self->{con}->is_my_nick($kicked_nick)) {
            
            if($self->{rejoin_on_kick}) {
               warn "* Rejoin automatically is set!\n";
            }

            sleep(2);
            $self->{con}->send_srv (JOIN => $channel);

            my $si = String::IRC->new($kicker_nick)->red->bold;

            $self->{con}->send_srv (PRIVMSG => $channel,"kicked by $si, behavior logged");
         }
      }
   );

   $self->{con}->reg_cb ('irc_privmsg'  => sub {
      my ($nick, $ircmsg) = @_;

      return unless 
         (defined $ircmsg) && 
         (exists $ircmsg->{prefix}) && 
         (exists $ircmsg->{params}) && 
         (ref($ircmsg->{params}) eq "ARRAY");

      my $who = $ircmsg->{prefix};

      # undef        TekDrone TekDrone!dubkat@oper.teksavvy.ca
      my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

      my $channel = $ircmsg->{params}[0];

      return unless ((defined $channel) && ($self->{con}->is_channel_name($channel)));

      my $message = $ircmsg->{params}[1];

      my $channel_list = $self->{con}->channel_list($channel);

      my $cmd = undef;
      if ( defined($cmd = List::MoreUtils::first_value { $message =~ /$command_prefix$_->{'regex'}/ } @commands) ) {

         print "$cmd->{'name'} was matched\n";

         if( defined $cmd->{acl}) {
            my $ret = $cmd->{acl}->($who, $message, $channel, $channel_list);

            warn "* ACL returned $ret\n";

            if($ret) {
               if(defined $cmd->{delegate}) {

                  warn "* Calling delegate ".$cmd->{name}."\n";

                  $cmd->{delegate}->($who, AnyEvent::IRC::Util::filter_colors($message), $channel, $channel_list);
               }
            }

         }
         else {
            warn "* Delegate not defined for $cmd->{'name'}\n";
         }
      }
   });

   $self->{con}->reg_cb ('debug_recv' => sub {
      my ($con, $msg) = @_;
      my $cmd = $msg->{command};
      my $params = join("\t", @{$msg->{params}});

      if(defined $msg->{prefix}) {
         my ($m,$nick,$ident) = $con->split_nick_mode ($msg->{prefix});
         warn "< " .$cmd."\t\t$nick\t".$params."\n";
      } else {
         warn "< " .$cmd."\t\t".$params."\n";
      }

      #print Dumper($msg),"\n";
   });

   $self->{con}->reg_cb ('debug_send' => sub {
      my ($con, $command, @params) = @_;

      #warn Dumper(@params),"\n";
      #warn Dumper($command),"\n";
      my $sent = "> " .$command."\t\t" . join("\t", @params) . "\n";
      warn $sent;
      #warn $sent;
   });

}

sub _start {
   my $self = shift;

   $self->_buildup();

   # $self->{con}->send_srv (PRIVMSG => 'dek',"Hello there!");

   $self->{con}->send_srv (JOIN => '#hadouken');

   $self->{con}->send_srv (PRIVMSG => '#hadouken',"i is retarded");

   my $server_count = scalar @{$self->{servers}};

   my ($host,$port) = split(/:/, $self->{servers}[int rand $server_count]);

   warn "* Using random server: $host\n";

   $self->{con}->connect ($host, $port, { nick => 'fartinato' });

   $self->{c}->wait;

   #return 1;
}

sub parse_calc_result {
   my ($self,$html) = @_;
   
   $html =~ s!<sup>(.*?)</sup>!^$1!g;
   $html =~ s!&#215;!*!g;

   my $res;
   my $p = HTML::TokeParser->new( \$html );
   while ( my $token = $p->get_token ) {
      next
         unless ( $token->[0] || '' ) eq 'S'
         && ( $token->[1]        || '' ) eq 'img'
         && ( $token->[2]->{src} || '' ) eq '/images/icons/onebox/calculator-40.gif';

      $p->get_tag('h2');
      $res = $p->get_trimmed_text('/h2');
      return $res;
   }

   return $res;
}

sub cidr2usable_v4 {

    my ($self, $bit) = @_;

    return (2 ** (32 - $bit));
    # return 1 << ( 32-$bit ); works but its fucking up my IDE lol
}

sub calc_netmask {

    my($self, $subnet) = @_;

    my($network, $netbit) = split(/\//, $subnet);

    my $bit = ( 2 ** (32 - $netbit) ) - 1;

    my ($full_mask)  = unpack("N", pack('C4', split(/\./, '255.255.255.255')));

    return join('.', unpack('C4', pack("N", ($full_mask ^ $bit))));
}

sub calc {
   my ($self, $expression) = @_;

   my $url = URI->new('http://www.google.com/search');
   $url->query_form(q => $expression);

   my $ret;
   my $response = $self->_webclient->get($url);

   if($response->is_success) {

      $ret = $self->parse_calc_result($response->content);

   } else {

      warn "calc failed with server response code ".$response->status_line."\n";

   }

   return $ret;
}

sub _webclient {
   my $self = shift;

   unless(defined $self->{wc} ) {

      $self->{wc} = LWP::UserAgent->new(
         agent => 'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1)',
         timeout => 60,
         ssl_opts => { verify_hostname => 0 }
      );

      require LWP::ConnCache;
      $self->{wc}->conn_cache(LWP::ConnCache->new( ));
      $self->{wc}->conn_cache->total_capacity(10);

      require HTTP::Cookies;
      $self->{wc}->cookie_jar(HTTP::Cookies->new);
   }

   return $self->{wc};
}

sub _test {
   my $self = shift;

   print $self->calc_netmask('172.19.0.0/16'),"\n";

   my $expr_parser = do{
   use Regexp::Grammars;

   our %cmds = ();

   $cmds{'menace'}='thekey';
   $cmds{'dek'}='hello';

    qr{
      <nocontext:>

      <findquote>

      <getquote>

      <rule: findquote>
         findquote \s* <uid>? \s* <query>

         <rule: uid>     <_user=ulist>
         <rule: query>   <_query=comment>

         <token: ulist>  <%cmds { [\w-/.]+ }>
         <token: comment> [\w\s*.]+

      <rule: getquote>
         getquote \s* <num>

         <rule: num>     <_index=validint>

         <token: validint> [\d]+


    }xms
};

   my $text = 'mv test.txt something.txt findquote fart haha getquote 55555 test';

    if ($text =~ $expr_parser) {
         print "MATCHED\n\n";
        # If successful, the hash %/ will have the hierarchy of results...

        warn Dumper \%/;
    }


   exit;
}

1;

package main;

   use Cwd ();

   my $daemon = CashBot->new_with_options(
      basedir => Cwd::abs_path(__FILE__),
      servers => ['irc.underworld.no:6667','irc.efnet.org:6667'],
      channels => [ '#hadouken' ],
      admin => 'dek@2607:fb98:1a::666',
      rejoin_on_kick => 1,
   );

   my ($command) = @{$daemon->extra_argv};

   defined $command || die "No command specified";

   $daemon->start   if $command eq 'start';
   $daemon->status  if $command eq 'status';
   $daemon->restart if $command eq 'restart';
   $daemon->stop    if $command eq 'stop';

   $daemon->_test   if $command eq 'test';

   warn($daemon->status_message) if defined $daemon->status_message;
   exit(($daemon->exit_code || 0));