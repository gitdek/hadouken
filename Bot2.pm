package CashBot;

use strict;
use warnings;

our $VERSION = '0.1';

#use Data::Printer alias => 'Dumper',colored => 1;
use Data::Dumper;

# use List::MoreUtils ':all';

use List::MoreUtils ();
use List::Util ();

use AnyEvent;
use AnyEvent::IRC::Client;

use HTML::TokeParser::Simple;

use LWP::UserAgent;
use Encode;
use JSON::XS qw( decode_json );

#my $c = AnyEvent->condvar;
#my $con = new AnyEvent::IRC::Client;

my $command_prefix = '!';

my @commands = ( {name => 'dq', regex => '(dq|delquote)\s.+?', cb => undef, delegate => undef, acl => undef },
                  {name => 'fq', regex => '(fq|findquote)\s.+?', cb => undef, delegate => undef, acl => undef },
                  {name => 'rq', regex => '(rq|randquote)$', cb => undef, delegate => undef, acl => undef },
                  {name => 'q',  regex => '(q|quote)\s.+?', cb => undef, delegate => undef, acl => undef },
                  {name => 'btc', regex => 'btc$', cb => undef, delegate => undef, acl => undef },
                  {name => 'ltc', regex => 'ltc$', cb => undef, delegate => undef, acl => undef },
                  {name => 'mitch', regex => 'mitch$', cb => undef, delegate => undef, acl => undef },
               );

sub new {
   my $class = shift;

   my $self = {@_};
   bless $self, $class;

   #state crap.
   $self->{connected} = 0;

   $self->{c} = AnyEvent->condvar;
   $self->{con} = AnyEvent::IRC::Client->new();

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

   print "* blacklisted called\n";

   return $ret;
   #return $self->_finalize($ret);
}

sub whitelisted {
   my $self = shift;

   my $who = shift;

   my $ret = 0;


   return $ret;
   #return $self->_finalize($ret);
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

      my $ua = LWP::UserAgent->new(
         agent => 'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1)',
         timeout => 60,
         ssl_opts => { verify_hostname => 0 }
      );
      
      my $request = HTTP::Request->new('GET', $url);
      my $response = $ua->request($request);
      $json = $self->jsonify($response->content);
   };

   if($@) {
      warn "Error: $@\n";
   }

   return $json;
}

sub _buildup {
   my $self = shift;


$self->add_func(name => 'btc', 
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my $json = $self->fetch_json('https://btc-e.com/api/3/ticker/btc_usd');

         my $ret = "[btc_usd] Last: $json->{btc_usd}->{last} Low: $json->{btc_usd}->{low} High: $json->{btc_usd}->{high} Avg: $json->{btc_usd}->{avg} Vol: $json->{btc_usd}->{vol}";

         $self->{con}->send_srv (PRIVMSG => $channel, $ret);

         return 1;
   },
      acl => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my $ret = _->global_acl($who, $message, $channel, $channel_list);

         # add in some other behavior here if needed.

         return $ret;
   });

   $self->add_func(name => 'ltc', 
      delegate => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my $json = $self->fetch_json('https://btc-e.com/api/3/ticker/ltc_usd');

         print Dumper($json),"\n";

         my $ret = "[ltc_usd] Last: $json->{ltc_usd}->{last} Low: $json->{ltc_usd}->{low} High: $json->{ltc_usd}->{high} Avg: $json->{ltc_usd}->{avg} Vol: $json->{ltc_usd}->{vol}";

         $self->{con}->send_srv (PRIVMSG => $channel, $ret);

         return 1;
   },
      acl => sub {
         my ($who, $message, $channel, $channel_list) = @_;

         my $ret = _->global_acl($who, $message, $channel, $channel_list);

         # add in some other behavior here if needed.

         return $ret;
   }, 
      cb => sub {
         print "* callback after mitch.\n";

         return 1;
   });

   $self->{con}->reg_cb (
      connect => sub {
         my ($con, $err) = @_;
         if (defined $err) {
            print "couldn't connect to server: $err\n";
         }
      },
      registered => sub {

         print "registered!\n";
         
         $self->{con}->enable_ping (60);
      },
      disconnect => sub {

         print "disconnected: $_[1]!\n";

         $self->{c}->broadcast;
      }
   );

   $self->{con}->reg_cb ('irc_privmsg'  => sub {
      my ($nick, $ircmsg) = @_;

      return unless 
         (defined $ircmsg) || 
         (exists $ircmsg->{prefix}) || 
         (exists $ircmsg->{params}) || 
         (ref($ircmsg->{params}) eq "ARRAY");

      my $who = $ircmsg->{prefix};

      # undef        TekDrone TekDrone!dubkat@oper.teksavvy.ca
      my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

      my $channel = $ircmsg->{params}[0];

      return unless ((defined $channel) || ($self->{con}->is_channel_name($channel)));

      my $message = $ircmsg->{params}[1];

      my $channel_list = $self->{con}->channel_list($channel);

      my $cmd = undef;
      if ( defined($cmd = List::MoreUtils::first_value { $message =~ /$command_prefix$_->{'regex'}/ } @commands) ) {

         print "$cmd->{'name'} was matched\n";

         if( defined $cmd->{acl}) {
            my $ret = $cmd->{acl}->($who, $message, $channel, $channel_list);

            print "* ACL returned $ret\n";

            if($ret) {
               if(defined $cmd->{delegate}) {

                  print "* Calling delegate\n";

                  $cmd->{delegate}->($who, $message, $channel, $channel_list);
               }
            }
         }
         else {
            print "Delegate not defined for $cmd->{'name'}\n";
         }
      }


      print "$who said $message in $channel\n\n";
   });

   $self->{con}->reg_cb ('debug_recv'  => sub {
      my ($con, $msg) = @_;
      print
         "< "
         . $con->mk_msg ($msg->{prefix}, $msg->{command}, @{$msg->{params}})
         . "\n";  
   });

   $self->{con}->reg_cb ('debug_send' => sub {
      my ($con, @msg) = @_;
      print "> " . $con->mk_msg (undef, @msg) . "\n"
   });

}

sub _start {
   my $self = shift;

   $self->_buildup;

   # $self->{con}->send_srv (PRIVMSG => 'dek',"Hello there!");

   $self->{con}->send_srv (JOIN => '#hadouken');

   $self->{con}->send_srv (PRIVMSG => '#hadouken',"i is retarded");

   $self->{con}->connect ("irc.efnet.org", 6667, { nick => 'fartinatorz' }); #reconnect => 1, timeout => 5

   $self->{c}->wait;
}


1;

package main;

my $cb = CashBot->new();

#test();
$cb->_start();

