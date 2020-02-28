package Hadouken::ZooKeeper;

use strict;
use warnings;

use ZooKeeper;
use ZooKeeper::XS;
use ZooKeeper::Constants;
use ZooKeeper::Transaction;
use AnyEvent;
use Module::Runtime qw(require_module);
use Sys::Hostname qw(hostname);
use POSIX qw(strftime);
use Time::HiRes qw(time);
use Moose;
use namespace::autoclean;

our $VERSION = '0.01';

=head1 NAME
 
Hadouken::ZooKeeper
 
=head1 Synopsis

  my $zk = Hadouken::ZooKeeper->new(hosts => 'localhost:2181');

=head1 STATUS
 
Unstable as fuck

=head1 DESCRIPTION
 
High level class for communicating with ZooKeeper
 
=back
 
=head1 ATTRIBUTES
 

=head2 timeout
 
The session timout used for the ZooKeeper connection.
 
=cut
 

has timeout => ( is => 'rw', isa => 'Int', default => sub { 30 } );

=head2 zk_servers
 
A comma separated list of ZooKeeper server hostnames and ports.
 
    'localhost:2181'
    'zoo1.domain:2181,zoo2.domain:2181'
 
=cut

has zk_servers   => (
    is      => 'rw',
    isa     => 'Str',
    default => sub { 'localhost:2181' }
);

has root_path   => (
    is      => 'rw',
    isa     => 'Str',
    default => sub { '/hadouken' }
);

has leader_elect_time => ( is => 'ro', isa => 'Str', writer   => '_set_leader_time' );

sub BUILD {
    my ($self, $args) = @_;

    $self->{zk_watch} = undef;
    $self->{c}   = AnyEvent->condvar;
}
 

sub gen_seq_name { hostname . ".PID.$$-" }
sub split_seq_name { shift =~ /^(.+-)(\d+)$/; $1, $2 }


sub _start {
	warn "START CALLED\n";

	my ($self, $args) = @_;
    $self->{zk} = ZooKeeper->new( hosts => $self->zk_servers );

    warn "CREATED NEW ZOOKEEPER";

    $self->{zk}->create($self->root_path) unless $self->{zk}->exists($self->root_path);

	my $lockname = gen_seq_name();
	my $path;
	$path .= $self->root_path;
	$path .= "/";
	$path .= $lockname;

	warn "Path:$path";

    my $lock = $self->{zk}->create(
        $path,
        ephemeral => 1, sequential => 1,
        acl => ZOO_OPEN_ACL_UNSAFE,
    );

	my ($basename, $n) = split_seq_name $lock;


}

sub DEMOLISH {
    warn "DEMOLISH ENTER";
}

sub DESTROY {

}


no Moose;
__PACKAGE__->meta->make_immutable;

1;

