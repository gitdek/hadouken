use AnyEvent;
use AnyEvent::IRC::Client;

my $c = AnyEvent->condvar;
my $con = new AnyEvent::IRC::Client;

$con->reg_cb (
   connect => sub {
      my ($con, $err) = @_;
      if (defined $err) {
         warn "Couldn't connect to server: $err\n";
      }
   },
   registered => sub {
      my ($self) = @_;
      warn "registered!\n";
      $con->enable_ping (60);
   },
   disconnect => sub {
      warn "disconnected: $_[1]!\n";
      $c->broadcast;
   }
);

$con->reg_cb ('irc_*' => sub {
   my @p = @{delete $_[1]->{params} || []};
   warn "DEBUG: " . join ('|', %{$_[1]}, @p) . "\n";
});

$con->reg_cb ('sent'  => sub {
   shift; warn "DEBUG SENT: " . join ('|', @_) . "\n";
});

#$con->send_srv (PRIVMSG => 'dek',"Hello there!");

$con->send_srv (JOIN => '#hadouken');

$con->send_srv (PRIVMSG => '#hadouken',"i is retarded");

$con->connect ("irc.efnet.org", 6667, { nick => 'fartinatorz' });

$c->wait;

$con->disconnect;

