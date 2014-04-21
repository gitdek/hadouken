#!/usr/bin/env perl

package CashBot;

use strict;
use warnings;
use diagnostics;

use 5.014;

our $VERSION = '0.2';
our $AUTHOR = 'dek';

#use Data::Dumper;
use Data::Printer alias => 'Dumper', colored => 1;

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
use Net::Whois::IP ();

use TryCatch;

use Moose;

with 'MooseX::Getopt::GLD' => { getopt_conf => [ 'pass_through' ] };

use namespace::autoclean;

has 'start_time' => (is => 'rw', isa => 'Str', required => 0);
has 'connect_time' => (is => 'rw', isa => 'Str', required => 0);
has 'safe_delay' => (is => 'rw', isa => 'Str', required => 0, default => '0.25');
has 'quote_limit' => (is => 'rw', isa => 'Str', required => 0, default => '3');

my $command_prefix = '^(!|\.|hadouken\s+|hadouken\,\s+)';

# Admin commands now privmsg the user instead of channel.
# Make sure to check acl's of each command.

my @commands = (
      {name => 'raw',            regex => 'raw\s.+?',                comment => 'send raw command',               require_admin => 1 }, 
      {name => 'statistics',     regex => '(stats|statistics)$',     comment => 'get statistics about bot',       require_admin => 1 },   
      {name => 'channeladd',     regex => 'channeladd\s.+?',         comment => 'add channel',                    require_admin => 1 },
      {name => 'channeldel',     regex => 'channeldel\s.+?',         comment => 'delete channel',                 require_admin => 1 },
      {name => 'powerup',        regex => '(powerup|power\^)$',      comment => 'power up +o',                    require_admin => 1 },
      {name => 'admindel',       regex => 'admindel\s.+?',           comment => 'delete admin <nick@host>',       require_admin => 1 },
      {name => 'adminadd',       regex => 'adminadd\s.+?',           comment => 'add admin <nick@host>',          require_admin => 1 },
      {name => 'whitelistdel',   regex => 'whitelistdel\s.+?',       comment => 'delete whitelist <nick@host>',   require_admin => 1 },
      {name => 'whitelistadd',   regex => 'whitelistadd\s.+?',       comment => 'add whitelist <nick@host>',      require_admin => 1 },
      {name => 'blacklistdel',   regex => 'blacklistdel\s.+?',       comment => 'delete blacklist <nick@host>',   require_admin => 1 },
      {name => 'blacklistadd',   regex => 'blacklistadd\s.+?',       comment => 'add blacklist <nick@host>',      require_admin => 1 },
      {name => 'shorten',        regex => 'shorten\s.+?',            comment => 'shorten <url>' },
      {name => 'whois',          regex => 'whois\s.+?',              comment => 'whois lookup <ip> or <domain>' }, 
      {name => 'ipcalc',         regex => 'ipcalc\s.+?',             comment => 'calculate ip netmask' },
      {name => 'calc',           regex => 'calc\s.+?',               comment => 'google calculator' },
      {name => 'ticker',         regex => 'ticker\s.+?',             comment => 'look up coin(ltc,doge,nmc) or coin pair(ltc_usd,doge_ltc,nvc_btc)' },
      {name => 'geoip',          regex => 'geoip\s.+?',              comment => 'geo ip lookup' },
      {name => 'lq',             regex => '(lq|lastquote)$',         comment => 'get most recently added quote' },
      {name => 'aq',             regex => '(aq|addquote)\s.+?',      comment => 'add a quote' },
      {name => 'dq',             regex => '(dq|delquote)\s.+?', ,    comment => 'delete quote' },
      {name => 'fq',             regex => '(fq|findquote)\s.+?',     comment => 'find a quote' },
      {name => 'rq',             regex => '(rq|randquote)$',         comment => 'get a random quote' },
      {name => 'q',              regex => '(q|quote)\s.+?',          comment => 'get a quote by index(es)' },
      {name => 'btc',            regex => 'btc$',                    comment => 'display btc ticker' },
      {name => 'ltc',            regex => 'ltc$',                    comment => 'display ltc ticker' },
      {name => 'eur2usd',        regex => '(e2u|eur2usd)$',          comment => 'display euro to usd ticker' },
      {name => 'commands',       regex => '(commands|cmds)$',        comment => 'display list of available commands' },
      {name => 'help',           regex => 'help$',                   comment => 'get help info' },
);

# TODO: Wildcard matching in whitelist's and blacklist's
# TODO: Whois command, finish up
# TODO: Add layer of encryption for admin stuff

sub new {
   my $class = shift;
   my $self = {@_};
   bless $self, $class;

   return $self;
}

sub stop {
   my ($self) = @_;
   return unless $self->{connected};

   if(defined $self->{con}) {
      # In our registered callback for disconnect we handle the state vars and condvar
      $self->{con}->disconnect();
   }
}

sub start {
   my ($self) = @_;
   
   if($self->{connected}) {
      $self->stop();
   }

   $self->start_time(time());
   $self->{connected} = 0;
   $self->{c} = AnyEvent->condvar;
   $self->{con} = AnyEvent::IRC::Client->new();
   $self->_start;
}

before 'send_server_safe' => sub {
   my $self = shift;

   Time::HiRes::sleep($self->safe_delay);
};

sub send_server_safe {
   my ($self,$command, @params) = @_;
   return unless defined $self->{con} && defined $command;
   $self->{con}->send_srv($command,@params);
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
# is_admin overrides everything.
# If you are +o or +v, and not on the blacklist you return OK.
# if you are neither +o or +v, we check the whitelist.
#

sub passive_acl {
   my $self = shift;
   my ($who, $message, $channel, $channel_list) = @_;

   my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

   if($self->is_admin($who)) {
      return 1;
   }

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

sub global_acl {
   my $self = shift;
   my ($who, $message, $channel, $channel_list) = @_;

   my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

   if($self->is_admin($who)) {
      return 1;
   }

   if(exists $channel_list->{$nickname}) {

      return 0 if($self->blacklisted($who));

      return 1 if($self->whitelisted($who));
   }

   return 0;
}

sub blacklisted {
   my ($self, $who) = @_;

   my ($nick,$host) = $self->get_nick_and_host($who);

   $nick = lc($nick);
   $host = lc($host);

   if(grep {lc($_->[0]) eq $nick && lc($_->[1]) eq $host } @{$self->{blacklistdb}}) {
      return 1;
   }

   return 0;
}

sub whitelisted {
   my ($self, $who) = @_;

   my ($nick,$host) = $self->get_nick_and_host($who);

   $nick = lc($nick);
   $host = lc($host);

   if(grep {lc($_->[0]) eq $nick && lc($_->[1]) eq $host } @{$self->{whitelistdb}}) {
      return 1;
   }

   return 0;
}

sub get_nick_and_host {
   my ($self, $who) = @_;
   my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
   my ($n_pre, $n_host);

   if (defined $ident && $ident ne '') {
      ($n_pre, $n_host) = split(/@/, $ident);
   } else {
      ($n_pre, $n_host) = split(/@/, $nickname);
      $nickname = $n_pre;
   }

   return ($nickname, $n_host);
}

sub is_admin {
   my ($self, $who) = @_;
   my ($nick,$host) = $self->get_nick_and_host($who);

   $nick = lc($nick);
   $host = lc($host);

   if(grep {lc($_->[0]) eq $nick && lc($_->[1]) eq $host } @{$self->{adminsdb}}) {
      return 1;
   }

   return 0;
}

sub admin_delete {
   my ($self, $who, $statement) = @_;

   return unless $self->is_admin($who) && defined $statement;

   my ($creator_nick,$creator_host) = $self->get_nick_and_host($who);

   my ($nick, $host) = $self->get_nick_and_host($statement);

   return unless defined($nick) && defined($host);

   my $index = -1;
   # Returns -1 if no such item could be found.
   if ( ($index = List::MoreUtils::first_index { $_->[0] eq $nick && $_->[1] eq $host } @{$self->{adminsdb}}) >= 0 ) {

      splice(@{$self->{adminsdb}}, $index, 1);

      return 1;
   }
}

sub admin_add {
   my ($self, $who, $statement) = @_;

   return unless $self->is_admin($who) && defined $statement;

   my ($creator_nick,$creator_host) = $self->get_nick_and_host($who);

   my ($nick, $host) = $self->get_nick_and_host($statement);

   return unless defined($nick) && defined($host);

   return if($self->is_admin($statement));

   my @admin_row = [$nick, $host, '*', time(), $creator_nick];

   push($self->{adminsdb}, @admin_row);

   return 1;
}

sub whitelist_add {
   my ($self, $who, $statement) = @_;

   return unless $self->is_admin($who) && defined $statement;

   my ($creator_nick,$creator_host) = $self->get_nick_and_host($who);

   my ($nick, $host) = $self->get_nick_and_host($statement);

   return unless defined($nick) && defined($host);

   return if($self->whitelisted($statement));

   my @whitelist_row = [$nick, $host, '*', time(), $creator_nick];

   push($self->{whitelistdb}, @whitelist_row);

   return 1;
}

sub whitelist_delete {
   my ($self, $who, $statement) = @_;

   return unless $self->is_admin($who) && defined $statement;

   my ($creator_nick,$creator_host) = $self->get_nick_and_host($who);

   my ($nick, $host) = $self->get_nick_and_host($statement);

   return unless defined($nick) && defined($host);

   my $index = -1;
   # Returns -1 if no such item could be found.
   if ( ($index = List::MoreUtils::first_index { $_->[0] eq $nick && $_->[1] eq $host } @{$self->{whitelistdb}}) >= 0 ) {

      splice(@{$self->{whitelistdb}}, $index, 1);

      return 1;
   }
}

sub blacklist_add {
   my ($self, $who, $statement) = @_;

   return unless $self->is_admin($who) && defined $statement;

   my ($creator_nick,$creator_host) = $self->get_nick_and_host($who);

   my ($nick, $host) = $self->get_nick_and_host($statement);

   return unless defined($nick) && defined($host);

   return if($self->blacklisted($statement));

   my @blacklist_row = [$nick, $host, '*', time(), $creator_nick];

   push($self->{blacklistdb}, @blacklist_row);

   return 1;
}

sub blacklist_delete {
   my ($self, $who, $statement) = @_;

   return unless $self->is_admin($who) && defined $statement;

   my ($creator_nick,$creator_host) = $self->get_nick_and_host($who);

   my ($nick, $host) = $self->get_nick_and_host($statement);

   return unless defined($nick) && defined($host);

   my $index = -1;
   # Returns -1 if no such item could be found.
   if ( ($index = List::MoreUtils::first_index { $_->[0] eq $nick && $_->[1] eq $host } @{$self->{blacklistdb}}) >= 0 ) {

      splice(@{$self->{blacklistdb}}, $index, 1);

      return 1;
   }
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
   $self->{adminsdb} = ();
   $self->{blacklistdb} = ();
   $self->{whitelistdb} = ();

   #my $redis = Redis->new;

   my $filedirname = File::Basename::dirname(Cwd::abs_path(__FILE__));

   $self->{geoip} = Geo::IP->open($filedirname.'/geoip/GeoIPCity.dat') or die $!;

   my $tieobj = tie @{$self->{quotesdb}}, 'Tie::Array::CSV', $filedirname.'/quotes.txt', memory => 20_000_000 or die $!;

   my $tieadminobj = tie @{$self->{adminsdb}}, 'Tie::Array::CSV', $filedirname.'/admins.txt' or die $!;

   my $tiewhitelistobj = tie @{$self->{whitelistdb}}, 'Tie::Array::CSV', $filedirname.'/whitelist.txt' or die $!;

   my $tieblacklistobj = tie @{$self->{blacklistdb}}, 'Tie::Array::CSV', $filedirname.'/blacklist.txt' or die $!;

   # Add ourselves into the db if we arent in already!
   unless ($self->is_admin($self->{admin})) {
      my ($nick,$host) = split(/@/,$self->{admin});
      my @admin_row = [$nick, $host, '*', time()];
      push($self->{adminsdb}, @admin_row);
   }

   my $simple_acl = sub {
      my ($who, $message, $channel, $channel_list) = @_;
      my $ret = $self->global_acl($who, $message, $channel, $channel_list);
      return $ret;
   };

   my $passive_acl = sub {
      my ($who, $message, $channel, $channel_list) = @_;
      my $ret = $self->passive_acl($who, $message, $channel, $channel_list);
      return $ret;
   };

   $self->add_func(name => 'powerup',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;
         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my $ref_modes = $self->{con}->nick_modes ($channel, $nickname);

         return unless defined $ref_modes;

         unless($ref_modes->{'o'}) {
            $self->send_server_safe( MODE => $channel, '+o', $nickname);
         }

         return 1;
    },
      acl => sub {
         my ($who, $message, $channel, $channel_list) = @_;
         my $ret = $self->is_admin($who);
         return $ret;
   });


   $self->add_func(name => 'channeldel',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my ($cmd, $arg) = split(/ /, lc($message), 2);

         return unless ((defined $arg) && ($self->{con}->is_channel_name($arg)));
         $self->send_server_safe (PART => $arg);

         return 1;
    },
      acl => sub {
         my ($who, $message, $channel, $channel_list) = @_;
         my $ret = $self->is_admin($who);
         return $ret;
   });

   $self->add_func(name => 'channeladd',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my ($cmd, $arg) = split(/ /, lc($message), 2);
         
         return unless ((defined $arg) && ($self->{con}->is_channel_name($arg)));
         $self->send_server_safe (JOIN => $arg);

         return 1;
    },
      acl => sub {
         my ($who, $message, $channel, $channel_list) = @_;
         my $ret = $self->is_admin($who);
         return $ret;
   });

   $self->add_func(name => 'admindel',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my ($cmd, $arg) = split(/ /, lc($message), 2);

         return unless defined $arg;

         my $del_ret = $self->admin_delete($who, $arg);

         if($del_ret) {
            my $out_msg = "[admindel] deleted admin $arg -> by $nickname";
            $self->send_server_safe (PRIVMSG => $nickname, $out_msg);
         }

         return 1;
    },
      acl => sub {
         my ($who, $message, $channel, $channel_list) = @_;
         my $ret = $self->is_admin($who);
         return $ret;
   });

   $self->add_func(name => 'adminadd',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;
         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
         my ($cmd, $arg) = split(/ /, lc($message), 2);

         return unless defined $arg;

         my $add_ret = $self->admin_add($who, $arg);

         if($add_ret) {
            my $out_msg = "[adminadd] added admin $arg -> by $nickname";

            $self->send_server_safe (PRIVMSG => $nickname, $out_msg);
         }

         return 1;
    },
      acl => sub {
         my ($who, $message, $channel, $channel_list) = @_;
         my $ret = $self->is_admin($who);
         return $ret;
   });

   $self->add_func(name => 'whitelistadd',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;
         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
         my ($cmd, $arg) = split(/ /, lc($message), 2);

         return unless defined $arg;

         my $add_ret = $self->whitelist_add($who, $arg);

         if($add_ret) {
            my $out_msg = "[whitelistadd] added whitelist $arg -> by $nickname";

            $self->send_server_safe (PRIVMSG => $nickname, $out_msg);
         }

         return 1;
    },
      acl => sub {
         my ($who, $message, $channel, $channel_list) = @_;
         my $ret = $self->is_admin($who);
         return $ret;
   });


   $self->add_func(name => 'whitelistdel',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my ($cmd, $arg) = split(/ /, lc($message), 2);

         return unless defined $arg;

         my $del_ret = $self->whitelist_delete($who, $arg);

         if($del_ret) {
            my $out_msg = "[whitelistdel] deleted whitelist $arg -> by $nickname";
            $self->send_server_safe (PRIVMSG => $nickname, $out_msg);
         }

         return 1;
    },
      acl => sub {
         my ($who, $message, $channel, $channel_list) = @_;
         my $ret = $self->is_admin($who);
         return $ret;
   });

  $self->add_func(name => 'blacklistadd',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;
         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
         my ($cmd, $arg) = split(/ /, lc($message), 2);

         return unless defined $arg;

         my $add_ret = $self->blacklist_add($who, $arg);

         if($add_ret) {
            my $out_msg = "[blacklistadd] added blacklist $arg -> by $nickname";

            $self->send_server_safe (PRIVMSG => $nickname, $out_msg);
         }

         return 1;
    },
      acl => sub {
         my ($who, $message, $channel, $channel_list) = @_;
         my $ret = $self->is_admin($who);
         return $ret;
   });


   $self->add_func(name => 'blacklistdel',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my ($cmd, $arg) = split(/ /, lc($message), 2);

         return unless defined $arg;

         my $del_ret = $self->blacklist_delete($who, $arg);

         if($del_ret) {
            my $out_msg = "[blacklistdel] deleted blacklist $arg -> by $nickname";
            $self->send_server_safe (PRIVMSG => $nickname, $out_msg);
         }

         return 1;
    },
      acl => sub {
         my ($who, $message, $channel, $channel_list) = @_;
         my $ret = $self->is_admin($who);
         return $ret;
   });

   $self->add_func(name => 'raw',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;
         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
         my ($cmd, $arg) = split(/ /, lc($message), 2);
         
         return unless defined $arg;

         my @send_params = split(/ /, $arg);
         return unless($#send_params >= 0);
         my $send_command = shift(@send_params);

         warn "Send command $send_command\n";
         warn "Params:\n";
         print Dumper(@send_params);

         $self->send_server_safe ($send_command, @send_params);

         return 1;
    },
      acl => sub {
         my ($who, $message, $channel, $channel_list) = @_;
         my $ret = $self->is_admin($who);
         return $ret;
   });

   $self->add_func(name => 'shorten',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;
         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
         
         my ($cmd, $arg) = split(/ /, $message, 2); # DO NOT LC THE MESSAGE!
         
         return unless defined $arg;

         my ($url,$title) = $self->_shorten($arg);
         
         if(defined $url && $url ne '') {
            if(defined $title && $title ne '') {
               $self->send_server_safe (PRIVMSG => $channel, "$url ($title)");
            } else {
               $self->send_server_safe (PRIVMSG => $channel, "$url");   
            }
         }

         return 1;
    },
      acl => sub {
         my ($who, $message, $channel, $channel_list) = @_;
         my $ret = $self->is_admin($who);
         return $ret;
   });

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
               ($network =~ /$RE{net}{IPv4}/);

         if( ($netbit =~ /^$RE{num}{int}$/) && 
               ($netbit <= 32) && 
               ($netbit >= 0)) {

            my $res_calc = $self->calc_netmask($network."\/".$netbit);

            my $res_usable = $self->cidr2usable_v4($netbit);

            return unless (defined $res_calc) || (defined $res_usable);

            my $out_msg = "[ipcalc] $arg -> netmask: $res_calc - usable addresses: $res_usable";

            $self->send_server_safe (PRIVMSG => $channel, $out_msg);
         } elsif($netbit =~ /$RE{net}{IPv4}/) {

            my $cidr = $self->netmask2cidr($netbit,$network);

            my $poop = "[ipcalc] $arg -> cidr $cidr";

            $self->send_server_safe (PRIVMSG => $channel, $poop);
         }

         return 1;
    },
      acl => $passive_acl,
   );

   $self->add_func(name => 'calc',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my ($cmd, $arg) = split(/ /, lc($message), 2);

         return unless (defined($arg) && length($arg));

         my $res_calc = $self->calc($arg);

         return unless defined $res_calc;

         $self->send_server_safe (PRIVMSG => $channel, "[calc] $res_calc");

         return 1;
   },
      acl => $passive_acl,
   );

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

         $self->send_server_safe (PRIVMSG => $channel, $ret);

         return 1;
   },
      acl => $passive_acl,
   );



   $self->add_func(name => 'whois',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my ($cmd, $arg) = split(/ /, lc($message), 2);

         return unless (defined($arg) && length($arg));

         if( $arg =~ /$RE{net}{IPv4}/ ) {

            my $record = Net::Whois::IP::whoisip_query($arg);

            print Dumper($record);


         } elsif ( $arg =~ m{($RE{URI})}gos ) {

            my $uri = URI->new($arg);
            my $host_only = $uri->host;

         } else {


         }  

         return 1;
   },
      acl => $simple_acl,
   );

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

            $self->send_server_safe (PRIVMSG => $channel, $ip_result);           

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
                     $self->send_server_safe (PRIVMSG => $channel, "$arg ($ip_addr) -> no results in db");
                     return;
                  }

                  my $dom_result = "$arg ($ip_addr) ->";
                  $dom_result .= " City:".$record->city if defined $record->city && $record->city ne '';
                  $dom_result .= " Region:".$record->region if defined $record->region && $record->region ne '';
                  $dom_result .= " Country:".$record->country_code if defined $record->country_code && $record->country_code ne '';

                  $self->send_server_safe (PRIVMSG => $channel, $dom_result);           
               } 
            );
         } else {
            try {
               warn "Trying Other..\n";

               #my $uri = URI->new($arg,'http');
               #my $host_only = $uri->host;
               AnyEvent::DNS::resolver->resolve ($arg, "a", sub {

                  my $row = List::MoreUtils::last_value { grep { $_ eq "a" } @$_  } @_;

                  return unless (defined $row) || (@$row[4] =~ /$RE{net}{IPv4}/);

                  my $ip_addr = @$row[4];

                  return unless ($ip_addr =~ /$RE{net}{IPv4}/);

                  my $record = $self->{geoip}->record_by_addr($ip_addr);   

                  unless(defined $record) {
                     $self->send_server_safe (PRIVMSG => $channel, "$arg ($ip_addr) -> no results in db");
                     return;
                  }

                  my $dom_result = "$arg ($ip_addr) ->";
                  $dom_result .= " City:".$record->city if defined $record->city && $record->city ne '';
                  $dom_result .= " Region:".$record->region if defined $record->region && $record->region ne '';
                  $dom_result .= " Country:".$record->country_code if defined $record->country_code && $record->country_code ne '';

                  $self->send_server_safe (PRIVMSG => $channel, $dom_result);
            });
         }
         catch($e) {
               warn "* GeoIP failled for $e\n";
         }
            # maybe implement by nick (in channel)
            # .geoip dek
            # if(exists $channel_list->{$nickname}) {
            # then do the lookup.
         }

         return 1;
    },
      acl => $simple_acl,
   );

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

         my $creator = undef;

         if($arg =~ m/creator:(\w+)/ ) {
            $creator = $1;
            $creator =~ s/^\s+//;
            $creator =~ s/\s+$//;

            #warn "creator: [$creator]\n";

            $arg =~ s/creator:(\w+)//;
         }

         $arg =~ s/^\s+//;
         $arg =~ s/\s+$//;
         #warn "searching for [$arg]\n";

         my @found;

         unless(defined $creator) {
            @found = List::MoreUtils::indexes { lc($_->[1]) =~ lc($arg) } @{$self->{quotesdb}};
         } else {

            @found = List::MoreUtils::indexes { $arg ne '' ? (lc($_->[1]) =~ lc($arg)) && (lc($_->[0]) =~ lc($creator)) : lc($_->[0]) =~ lc($creator) } @{$self->{quotesdb}};

            #if(defined $arg && $arg ne '') {
            #   @found = List::MoreUtils::indexes { (lc($_->[1]) =~ lc($arg)) && (lc($_->[0]) =~ lc($creator)) } @{$self->{quotesdb}};
            #} else {
            #   @found = List::MoreUtils::indexes { lc($_->[0]) =~ lc($creator) } @{$self->{quotesdb}};
            #}
         }

         my $found_count = scalar @found;

         unless($found_count > 0) {
            $self->send_server_safe (PRIVMSG => $channel, 'nothing found in quotes!');
            return;
         }

         my $si = String::IRC->new($found_count)->bold;

         $self->send_server_safe (PRIVMSG => $channel, 'found '.$si.' quotes!');

         my $limit = 0;
         foreach my $z (@found) {

            $limit++;
            last if($limit > $self->quote_limit);

            my @the_quote = $self->{quotesdb}[$z];
            my ($q_mode_map,$q_nickname,$q_ident) = $self->{con}->split_nick_mode($the_quote[0][0]);
            my $epoch_string = strftime "%a %b%e %H:%M:%S %Y", localtime($the_quote[0][3]);

            $self->send_server_safe (PRIVMSG => $channel, '['.int($z + 1).'/'.$quote_count.'] '.$the_quote[0][1].' - added by '.$q_nickname.' on '.$epoch_string);
         }

         return 1;
    },
      acl => $simple_acl,
   );

   $self->add_func(name => 'rq',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my $quote_count = scalar @{$self->{quotesdb}};

         return unless($quote_count > 0);

         my $rand_idx = int(rand($quote_count));

         my @rand_quote = $self->{quotesdb}[$rand_idx];

         #my ($q_mode_map,$q_nickname,$q_ident) = $self->{con}->split_nick_mode($rand_quote[0][0]);

         #my $epoch_string = strftime "%a %b%e %H:%M:%S %Y", localtime($rand_quote[0][3]);

         $self->send_server_safe (PRIVMSG => $channel, '['.int($rand_idx + 1).'/'.$quote_count.'] '.$rand_quote[0][1]);

         # $self->send_server_safe (PRIVMSG => $channel, '['.int($rand_idx + 1).'/'.$quote_count.'] '.$rand_quote[0][1].' - added by '.$q_nickname.' on '.$epoch_string);
      
         return 1;
    },
      acl => $passive_acl,
   );

   $self->add_func(name => 'dq',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my ($cmd, $arg) = split(/ /,$message, 2);

         return unless (defined $arg) && (length $arg);

         my $quote_count = scalar @{$self->{quotesdb}};

         return unless $arg =~ m/^\d+$/;

         unless( (int($arg) <= $quote_count) && (int($arg) > 0 ) ) {
            return;
         }

         splice(@{$self->{quotesdb}}, (int($arg) - 1), 1);

         #my $si = String::IRC->new($arg)->bold;

         $self->send_server_safe (PRIVMSG => $channel, 'Quote #'.$arg.' has been deleted.');

         return 1;
    },
      acl => $simple_acl,
   );

   $self->add_func(name => 'q',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my ($cmd, $arg) = split(/ /,$message, 2);

         return unless (defined $arg) && (length $arg);

         my $quote_count = scalar @{$self->{quotesdb}};

         return unless $quote_count > 0;

         my @real_indexes = ();

         while($arg =~ /$RE{num}{int}{-sep => ','}{-keep}/g) {
            push(@real_indexes,int($1 - 1));
         }

         while($arg =~ /$RE{num}{int}{-sep => ' '}{-keep}/g) {
            push(@real_indexes,int($1 - 1));
         }
    

         #warn "quote limit is ".$self->quote_limit." wtf\n";

         my @x = List::MoreUtils::distinct @real_indexes;

         return unless(@x);

         splice @x, $self->quote_limit if($#x >= $self->quote_limit );

         my $search_count = scalar @x;

         foreach my $j (@x) {
            next unless $j >=0 && $j < $quote_count;

            my @curr_quote = $self->{quotesdb}[$j]; # Don't dereference this.

            #print Dumper(@curr_quote);

            my $col_who       = $curr_quote[0][0];
            my $col_quote     = $curr_quote[0][1];
            my $col_channel   = $curr_quote[0][2];
            my $col_time      = $curr_quote[0][3];

            next 
               unless 
                  defined($col_who) && $col_who ne '' && 
                  defined($col_quote) && $col_quote ne '' && 
                  defined($col_channel) && $col_channel ne '' && 
                  defined($col_time) && $col_time ne '';

            my ($q_mode_map,$q_nickname,$q_ident) = $self->{con}->split_nick_mode($col_who);
            my $epoch_string = strftime "%a %b%e %H:%M:%S %Y", localtime($col_time);

            my $si1 = String::IRC->new('[')->black;
            my $si2 = String::IRC->new(int($j+1))->red('black')->bold;
            my $si3 = String::IRC->new('/'.$quote_count)->yellow('black');
            my $si4 = String::IRC->new('] '.$col_quote.' - added by '.$q_nickname.' on '.$epoch_string)->black;

            my $msg = "$si1$si2$si3$si4";

            $self->send_server_safe (PRIVMSG => $channel, $msg); #$si1.''.$si2.''.$si3.''.$si4
         }

         return 1;
    },
      acl => $passive_acl,
   );


   $self->add_func(name => 'lq',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my $quote_count = scalar @{$self->{quotesdb}};

         if ($quote_count > 0) {

            my @last_quote = $self->{quotesdb}[int($quote_count - 1)];

            my ($q_mode_map,$q_nickname,$q_ident) = $self->{con}->split_nick_mode($last_quote[0][0]);

            my $epoch_string = strftime "%a %b%e %H:%M:%S %Y", localtime($last_quote[0][3]);

            $self->send_server_safe (PRIVMSG => $channel, '['.$quote_count.'] '.$last_quote[0][1].' - added by '.$q_nickname.' on '.$epoch_string);
         }

         return 1;
    },
      acl => $simple_acl,
   );

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
      acl => $simple_acl,
   );

   $self->add_func(name => 'commands',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         #my $cmd_names = _->pluck(\@commands, 'name');

         my @copy = @commands;

         my $iter = List::MoreUtils::natatime 2, @copy;

         my $si1 = String::IRC->new('Available Commands:')->bold;

         $self->send_server_safe (PRIVMSG => $nickname, $si1);

         while( my @tmp = $iter->() ){

            my $command_summary = '';

            foreach my $c (@tmp) {

               if($c->{require_admin}) {
                  next unless $self->is_admin($who);
               }

               next 
                  unless 
                     defined($c->{name}) && $c->{name} ne '' && 
                     defined($c->{comment}) && $c->{comment} ne '';

               my $si = String::IRC->new($c->{name})->bold;
               $command_summary .= '['.$si.'] -> '.$c->{comment}."  ";
            }

            $self->send_server_safe (PRIVMSG => $nickname, $command_summary);
            undef $command_summary;
         }

         return 1;
    },
      acl => $simple_acl,
   );

   $self->add_func(name => 'help',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         #my $cmd_names = _->pluck(\@commands, 'name');

         my $si = String::IRC->new('Hi '.$nickname.', type .commands in the channel.')->bold;

         $self->send_server_safe (PRIVMSG => $nickname, $si);

         return 1;
    },
      acl => $simple_acl,
   );

   $self->add_func(name => 'statistics',
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my $si = String::IRC->new('Hi '.$nickname.', no statistics available.')->bold;

         $self->send_server_safe (PRIVMSG => $nickname, $si);

         return 1;
    },
      acl => sub {
         my ($who, $message, $channel, $channel_list) = @_;
         my $ret = $self->is_admin($who);
         return $ret;
   });

   $self->add_func(name => 'btc', 
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

         my $json = $self->fetch_json('https://btc-e.com/api/3/ticker/btc_usd');
         my $json2 = $self->fetch_json('https://crypto-trade.com/api/1/ticker/btc_usd');

         my $ret =  "[btc_usd\@btce] Last: $json->{btc_usd}->{last} Low: $json->{btc_usd}->{low} High: $json->{btc_usd}->{high} Avg: $json->{btc_usd}->{avg} Vol: $json->{btc_usd}->{vol}";
         my $ret2 = "[btc_usd\@ct]   Last: $json2->{data}->{last} Low: $json2->{data}->{low} High: $json2->{data}->{high} Vol(usd): $json2->{data}->{vol_usd}";

         $self->send_server_safe (PRIVMSG => $channel, $ret);

         $self->send_server_safe (PRIVMSG => $channel, $ret2);

         return 1;
   },
      acl => $passive_acl,
   );

   $self->add_func(name => 'ltc', 
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my $json = $self->fetch_json('https://btc-e.com/api/3/ticker/ltc_usd');

         my $json2 = $self->fetch_json('https://crypto-trade.com/api/1/ticker/ltc_usd');

         my $ret =  "[ltc_usd\@btce] Last: $json->{ltc_usd}->{last} Low: $json->{ltc_usd}->{low} High: $json->{ltc_usd}->{high} Avg: $json->{ltc_usd}->{avg} Vol: $json->{ltc_usd}->{vol}";
         
         my $ret2 = "[ltc_usd\@ct]   Last: $json2->{data}->{last} Low: $json2->{data}->{low} High: $json2->{data}->{high} Vol(usd): $json2->{data}->{vol_usd}";

         $self->send_server_safe (PRIVMSG => $channel, $ret);

         $self->send_server_safe (PRIVMSG => $channel, $ret2);

         return 1;
   },
      acl => $passive_acl,
   );


   $self->add_func(name => 'eur2usd', 
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my $json = $self->fetch_json('https://btc-e.com/api/3/ticker/eur_usd');

         my $ret = "[eur_usd] Last: $json->{eur_usd}->{last} Low: $json->{eur_usd}->{low} High: $json->{eur_usd}->{high} Avg: $json->{eur_usd}->{avg} Vol: $json->{eur_usd}->{vol}";

         $self->send_server_safe (PRIVMSG => $channel, $ret);

         return 1;
   },
      acl => $passive_acl,
   );

   $self->{con}->reg_cb (
      connect => sub {
         my ($con, $err) = @_;
         if (defined $err) {
            warn "* Couldn't connect to server: $err\n";
         }
      },
      registered => sub {
         $self->{connected} = 1;
         $self->connect_time(time());
      },
      disconnect => sub {

         warn "* Disconnected\n";

         $self->{connected} = 0;

         $self->{c}->broadcast;
      },
      join => sub {
         my ($con,$nick, $channel, $is_myself) = (@_);

         return if $is_myself;

         my $ident = $con->nick_ident($nick);

         return unless defined $ident;

         if($self->is_admin($ident)) {
            $self->send_server_safe( MODE => $channel, '+o', $nick);   
         }

      },
      kick => sub {
         my($con, $kicked_nick, $channel, $is_myself, $msg, $kicker_nick) = (@_);

         warn "* KICK CALLED -> $kicked_nick by $kicker_nick from $channel with message $msg -> is myself: $is_myself!\n";

         # warn "my nick is ". $self->{con}->nick() ."\n";

         if($self->{con}->nick() eq $kicked_nick || $self->{con}->is_my_nick($kicked_nick)) {
            
            if($self->{rejoin_on_kick}) {
               warn "* Rejoin automatically is set!\n";
            }

            sleep(2);
            $self->send_server_safe (JOIN => $channel);

            my $si = String::IRC->new($kicker_nick)->red->bold;

            $self->send_server_safe (PRIVMSG => $channel,"kicked by $si, behavior logged");
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

      my $message = $ircmsg->{params}[1];

      my $channel_list = $self->{con}->channel_list($channel);

      my $cmd = undef;
      if ( defined($cmd = List::MoreUtils::first_value { $message =~ /$command_prefix$_->{'regex'}/ } @commands) ) {

         unless($self->is_admin($who) && $cmd->{'require_admin'}) {
            return unless ((defined $channel) && ($self->{con}->is_channel_name($channel)));
         }

         print "* Command $cmd->{'name'} was matched\n";

         $message =~ s/$command_prefix//g;

         if( defined $cmd->{acl}) {
            my $ret = $cmd->{acl}->($who, $message, $channel || undef, $channel_list || undef);

            warn "* Command $cmd->{'name'} -> ACL returned $ret\n";

            if($ret) {
               if(defined $cmd->{delegate}) {

                  warn "* Command $cmd->{'name'} -> Calling delegate\n";

                  $cmd->{delegate}->($who, AnyEvent::IRC::Util::filter_colors($message), $channel, $channel_list);
               }
            }

         }
         else {
            warn "* Delegate not defined for $cmd->{'name'}\n";
         }
      } else {

         if ( $message =~ m{($RE{URI})}gos ) {

            my ($shrt_url,$shrt_title) = $self->_shorten($message);

            if(defined($shrt_url) && $shrt_url ne '') {

               if(defined($shrt_title) && $shrt_title ne '') {
                  $self->send_server_safe (PRIVMSG => $channel, "$shrt_url ($shrt_title)");
               } else {
                  $self->send_server_safe (PRIVMSG => $channel, "$shrt_url");      
               }

            }
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
   });

   $self->{con}->reg_cb ('debug_send' => sub {
      my ($con, $command, @params) = @_;
      my $sent = "> " .$command."\t\t" . join("\t", @params) . "\n";
      warn $sent;
   });

}

sub _start {
   my $self = shift;

   $self->_buildup();

   my $server_count = scalar @{$self->{servers}};
   my $server_hashref = $self->{servers}[int rand $server_count];

   my @servernames = keys $server_hashref;
   my $server_name = $servernames[0];

   $self->{server_name} = $server_hashref->{$server_name};

   foreach my $chan ( @{$server_hashref->{$server_name}{channel}} ) {

      $chan = "#".$chan unless($chan =~ m/^\#/g); # Append # if doesn't begin with.

      warn "* Joining $chan\n";

      $self->send_server_safe (JOIN => $chan);
   }

   # When connecting, sometimes if a nick is in use it requires an alternative.
   my $nick_change = sub {
      my ($badnick) = @_;
      $self->{nick} .= "_";
      return $self->{nick};
   };

   $self->{con}->set_nick_change_cb($nick_change);

   $self->{con}->connect ($server_hashref->{$server_name}{host}, $server_hashref->{$server_name}{port}, { nick => $self->{nick}, password => $server_hashref->{$server_name}{password}, send_initial_whois => 1});

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

sub netmask2cidr {
   my ($self,$mask, $network) = @_;
   my @octet = split (/\./, $mask);
   my @bits;
   my $binmask;
   my $binoct;
   my $bitcount = 0;

   foreach (@octet) {
      $binoct = unpack("B32", pack("N", $_));
      $binmask = $binmask . substr $binoct, -8;
   }

   @bits = split (//,$binmask);
   foreach (@bits) {
      $bitcount++ if ($_ eq "1");
   }

   my $cidr = $network . "/" . $bitcount;
   return $cidr;
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
      $ret =~ s/[^[:ascii:]]+//g;

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

sub _shorten {
   my $self = shift;
   my $url = shift;
   
   my $shortenurl = '';
   my $title = '';

   try {

      return 
         unless 
            exists $self->{bitly_api_key} && $self->{bitly_api_key} ne '' && 
            exists $self->{bitly_user_id} && $self->{bitly_user_id} ne '';

      my $api2 = "https://api-ssl.bitly.com/v3/shorten?access_token=".$self->{bitly_api_key}."&longUrl=$url";

      my $json = $self->fetch_json($api2);

      if(exists $json->{'data'} && exists $json->{'data'}->{'url'}) {

         $shortenurl = $json->{'data'}{'url'};

         my $response = $self->_webclient->get($url);

         my $p = HTML::TokeParser->new( \$response->decoded_content );
         if ($p->get_tag("title")) {
            $title = $p->get_trimmed_text;
         }

         #my $api3 = "https://api-ssl.bitly.com/v3/info?access_token=".$self->{bitly_api_key}."&shortUrl=$shortenurl";
         #my $json2 = $self->fetch_json($api3);
         #$title = $json2->{'data'}{'info'}{'title'};
      }
   }
   catch($e) {
      $shortenurl = '';
      warn "Error occured at shorten with url $url - $e";
   }

   return ($shortenurl,$title);
}

#sub _test {
#   my $self = shift;

#   print $self->calc_netmask('172.19.0.0/16'),"\n";

#   my $expr_parser = do{
#   use Regexp::Grammars;

#   our %cmds = ();

#   $cmds{'menace'}='thekey';
#   $cmds{'dek'}='hello';

#    qr{
#      <nocontext:>
#
#      <findquote>

#      <getquote>

#      <rule: findquote>
#         findquote \s* <uid>? \s* <query>
#
#         <rule: uid>     <_user=ulist>
#         <rule: query>   <_query=comment>
#
#         <token: ulist>  <%cmds { [\w-/.]+ }>
#         <token: comment> [\w\s*.]+

#      <rule: getquote>
#         getquote \s* <num>

#         <rule: num>     <_index=validint>

#         <token: validint> [\d]+


#    }xms
#};

#   my $text = 'mv test.txt something.txt findquote fart haha getquote 55555 test';

#    if ($text =~ $expr_parser) {
#         print "MATCHED\n\n";
        # If successful, the hash %/ will have the hierarchy of results...

#        warn Dumper \%/;
#    }


#   exit;
#}

1;

package main;

   use strict;
   use warnings;

   use Cwd ();

   use File::Basename();

   use Daemon::Control;

   # use Data::Printer alias => 'Dumper',colored => 1;

   use Config::General;

   use TryCatch;

   use namespace::autoclean;

   my $filedirname = File::Basename::dirname(Cwd::abs_path(__FILE__));

   my $conf = Config::General->new(-ForceArray => 1, -ConfigFile => $filedirname."/hadouken.conf", -AutoTrue => "yes") or die "Config file missing!";
   my %config = $conf->getall;

  # unless(exists $config{host} && $config{host} ne '' && exists $config{port} && $config{port} ne '') {
  #    die "Missing config items: host and/or port.\n";
  # }

   my $cb = CashBot->new_with_options(
      nick => 'hadouken',
      servers => [ $config{server} ],
      admin => $config{admin},
      rejoin_on_kick => 1,
      quote_limit => $config{quote_limit} || '2',
      safe_delay => $config{safe_delay} || '0.25',
      bitly_user_id => $config{bitly_user_id} || '', # To disable shortening, remove from config!
      bitly_api_key => $config{bitly_api_key} || '',
   );

   my $daemon = Daemon::Control->new(
      name        => "Hadouken",
      lsb_start   => '$syslog $remote_fs',
      lsb_stop    => '$syslog',
      lsb_sdesc   => 'Hadouke bot',
      lsb_desc    => 'Hadouken bot by dek',

      program => sub { $cb->start },

      help => "What?\n\n",
      kill_timeout => 6,

      pid_file    => $filedirname.'/hadouken.pid',
      stderr_file => $filedirname.'/hadouken.out',
      stdout_file => $filedirname.'/hadouken.out',

      fork        => 2,
   );

   my ($command) = @{$cb->extra_argv};

   defined $command || die "No command specified";

   my $exit_code;

   if ($command eq 'stop') {
      $daemon->pretty_print("Shutting Down", "red") if(defined $cb->start_time && $cb->start_time ne '');

      $cb->stop(); # Clean disconnect.

      $exit_code = $daemon->run_command('stop');
      exit($exit_code || 0);
   }

   try {
      $exit_code = $daemon->run_command($command);
   }
   catch (Str $e where { $_ =~ /^Error: undefined action/i } ) {
      warn "You must specify an action.\n";
   }
   catch($e) {
      warn $e,"\n";
   }

   exit(($exit_code || 0));