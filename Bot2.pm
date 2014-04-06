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

#my ($command_len_min, $command_len_max) = (sort {length($a) <=> length($b)} @commands)[0,-1];

# if +o or +v, you are permitted, unless you are on the blacklist.
# if not +o or +v, check if person is on whitelist.

# 'acl'

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

sub _buildup {
   my $self = shift;

   $self->add_func(name => 'mitch', 
      delegate => sub {
         # http://en.wikiquote.org/wiki/Mitch_Hedberg
         print "Delegate for mitch called!\n";

         my ($who, $message, $channel, $channel_list) = @_;

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
   }
   );

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



package main;

my $cb = CashBot->new();

$cb->_start();
