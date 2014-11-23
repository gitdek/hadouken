##############################################
# Hadouken
# 
#

#package Hadouken::Configuration;
#
#use strict;
#use warnings;
#
#use Moose;
#
##use Redis;
#
#
##has redis => (is => 'rw', isa => 'Redis', default => sub { my $redis = Redis->new(server => '127.0.0.1:6379'); $redis; });
#
#sub new {
#    my $class = shift;
#    my $self = {@_};
#    bless $self, $class;
#    return $self;
#}
#
##__PACKAGE__->meta->make_immutable;
#
#1;

package Hadouken;

use strict;
use warnings;
#use diagnostics;
#no strict "refs";

use FindBin qw($Bin);
use lib "$Bin/../lib";

use constant BIT_ADMIN => 0;
use constant BIT_WHITELIST => 1;
use constant BIT_BLACKLIST => 2;
use constant BIT_OP => 3;
use constant BIT_VOICE => 4;
use constant BIT_BOT => 5;

use constant CMODE_OP_ADMIN => 'O';
use constant CMODE_OP_WHITELIST => 'W';
use constant CMODE_PROTECT_ADMIN => 'P';
use constant CMODE_PROTECT_WHITELIST => 'V';
use constant CMODE_SHORTEN_URLS => 'U';
use constant CMODE_AGGRESSIVE => 'A';
use constant CMODE_PLUGINS_ALLOWED => 'Z';
use constant CMODE_FAST_OP => 'F'; # Do not create cookies when setting +o.
# 
# use 5.014;

our $VERSION = '0.8.6';
our $AUTHOR = 'dek';

use Data::Printer alias => 'Dumper', colored => 1;
#use Data::Dumper;

use Hadouken::DH1080;
use AsyncSocket;


use Scalar::Util ();
use Cwd ();
use List::MoreUtils ();
use List::Util ();
use AnyEvent;
use AnyEvent::IRC::Client;
use AnyEvent::DNS;
use AnyEvent::IRC::Util ();
use AnyEvent::Whois::Raw;
use HTML::TokeParser;
use URI ();
use LWP::UserAgent ();
use Encode qw( encode decode );
use Encode::Guess;
use JSON; # qw( encode_json decode_json );
use POSIX qw(strftime);
use Time::HiRes qw( sleep usleep nanosleep time gettimeofday);
use Geo::IP;
use Tie::Array::CSV;
use Regexp::Common;
use String::IRC;
use Crypt::RSA;
use Convert::PEM;
use MIME::Base64 ();
use Crypt::OpenSSL::RSA;
use Crypt::Blowfish;
use Crypt::CBC;
use Digest::SHA3 qw(sha3_256_hex);
use Digest::SHA;
use Config::General;
use Time::Elapsed ();
use TryCatch;
#use Redis;

$Net::Whois::Raw::CHECK_FAIL = 1;

use Moose;

with 'MooseX::Getopt::GLD' => { getopt_conf => [ 'pass_through' ] };

use namespace::autoclean;

use File::Spec;
use FindBin qw($Bin);
use Module::Pluggable search_dirs => [ "$Bin/plugins/" ], sub_name => '_plugins';

has start_time => (is => 'ro', isa => 'Str', writer => '_set_start_time');
has connect_time => (is => 'ro', isa => 'Str', writer => '_set_connect_time');
has safe_delay => (is => 'rw', isa => 'Str', required => 0, default => '0.25', trigger => \&_safedelay_set);
has quote_limit => (is => 'rw', isa => 'Str', required => 0, default => '3');

has keyx_cbc => (is => 'rw', isa => 'Int', required => 0, default => 0);

has loaded_plugins => (
    is => 'rw',
    isa => 'HashRef[Object]',
    lazy_build => 1,
    traits => [ 'Hash' ],
    handles => { _plugin => 'get' },
);

my $command_prefix = '^(\.|hadouken\s+|hadouken\,\s+)'; # requested remove of ! by nesta.

use constant B64 =>
'./0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

# MODES:
# +O  - auto op_admins
# +W  - auto op whitelist
# +P  - protect admins
# +V  - protect whitelist
# +U  - automatically shorten urls
# +A  - aggressive mode (kick/ban instead of -o, etc)
# +Z  - allow plugins to be used in this channel
# +F  - fast op (no cookies)

my @channelmodes = (
    {mode => 'O', 'comment' => 'automatically op admins'},
    {mode => 'W', 'comment' => 'automatically op whitelist'},
    {mode => 'P', 'comment' => 'protect admins'},
    {mode => 'V', 'comment' => 'protect whitelists'},
    {mode => 'U', 'comment' => 'automatically shorten urls'},
    {mode => 'A', 'comment' => 'aggressive protection mode'},
    {mode => 'Z', 'comment' => 'allow plugins to be used in this channel'},
    {mode => 'F', 'comment' => 'fast op with no cookies'}
);

my @commands = (
    {name => 'trivia',              regex => 'trivia\s.+?',             comment => 'trivia <command>',               require_admin => 1, channel_only => 1 }, 
    {name => 'raw',                 regex => 'raw\s.+?',                comment => 'send raw command',               require_admin => 1 }, 
    {name => 'statistics',          regex => '(stats|statistics)$',     comment => 'get statistics about bot',       require_admin => 1 },   
    {name => 'powerup',             regex => '(powerup|power\^)$',      comment => 'power up +o',                    require_admin => 1, channel_only => 1 },
    #{name => 'lq',                  regex => '(lq|lastquote)$',         comment => 'get most recently added quote', channel_only => 1 },
    #{name => 'aq',                  regex => '(aq|addquote)\s.+?',      comment => 'add a quote', channel_only => 1 },
    #{name => 'dq',                  regex => '(dq|delquote)\s.+?', ,    comment => 'delete quote', channel_only => 1 },
    #{name => 'fq',                  regex => '(fq|findquote)\s.+?',     comment => 'find a quote', channel_only => 1 },
    #{name => 'rq',                  regex => '(rq|randquote)$',         comment => 'get a random quote', channel_only => 1 },
    #{name => 'q',                   regex => '(q|quote)\s.+?',          comment => 'get a quote by index(es)', channel_only => 1 },
    {name => 'commands',            regex => '(commands|cmds)$',        comment => 'display list of available commands' },
    {name => 'plugins',             regex => 'plugins$',                comment => 'display list of available plugins' },
    {name => 'help',                regex => 'help.*?',                 comment => 'get help info' },
    {name => 'plugin',              regex => 'plugin\s.+?',             comment => 'plugin <name> <command>',       require_admin => 1 },
    {name => 'admin',               regex => 'admin\s.+?',              comment => 'admin <command> <args>',        require_admin => 1 },
    {name => 'whitelist',           regex => 'whitelist\s.+?',          comment => 'whitelist <command> <args>',    require_admin => 1 },
    {name => 'blacklist',           regex => 'blacklist\s.+?',          comment => 'blacklist <command> <args>',    require_admin => 1 },
    {name => 'channel',             regex => 'channel\s.+?',            comment => 'channel <command> <args>',      require_admin => 1 },
);

# TODO: Move trivia commands to plugins.
# Go back to Redis.
#

sub new {
    my $class = shift;
    my $self = {@_};
    bless $self, $class;
    return $self;
}

sub _safedelay_set {
    my ( $self, $delay, $old_delay ) = @_;

    return unless defined $delay && $delay > 0;

    my $micro_delay = $delay * 1_000_000;
    $self->getset('safe_micro_delay', $micro_delay);
}

sub getset {
    my $self = shift;
    my $field = shift;
    my $new = shift;  # optional

    my $old = $self->{$field};
    $self->{$field} = $new if defined $new;
    return $old;
}

sub isSet {
    { use integer;
        my ($self,$userFlags,$flagNum) = @_;

        my $mask = (1 << $flagNum);

        return ($userFlags & $mask);
    }
}

sub removeFlag {
    { use integer;
        my ($self,$userFlags,$flagPos) = @_;

        my $mask = (1 << $flagPos);
        $userFlags = ($userFlags & ~$mask);
        return $userFlags;
    }
}

sub addFlag {
    { use integer;
        my ($self,$userFlags,$flagPos) = @_;

        my $mask = (1 << $flagPos);
        $userFlags = ($userFlags | $mask);
        return $userFlags;
    }
}

sub available_modules {
    my $self = shift;

    my @central_modules =
    map {
    my $mod = $_;
    $mod =~ s/^Hadouken::Plugin:://;
    $mod;
    } _plugins();

    my @local_modules =
    map { substr( ( File::Spec->splitpath($_) )[2], 0, -3 ) } glob('./*.pm'),
    glob('./plugins/*.pm');

    my @modules = sort @local_modules, @central_modules;

    return @modules;            
}

sub _build_loaded_plugins {
    my ($self) = @_;

    my %loaded_plugins;
    for my $plugin ($self->available_modules) {

        my $m = undef;
        my $command_regex = undef;

        try {
            $m = $self->load($plugin);

            # Make sure not a blank regex.
            $m = undef unless $m->can('command_regex');
            $command_regex = $m->command_regex;

            $m = undef unless defined $command_regex && $command_regex ne '';

            $m = undef unless $m->can('command_name');
            $m = undef unless $m->can('command_comment');
            $m = undef unless $m->can('acl_check');
            $m = undef unless $m->can('command_run');
        }
        catch($e) {
            $m = undef;
            warn "Plugin $plugin failed to load: $e";
        }

        next unless defined $m;

        $loaded_plugins{$plugin} = $m;

        my $ver = $m->VERSION || '0.0';

        warn "Plugin $plugin $ver added successfully.\n";
    }

    return \%loaded_plugins;
}


# Case sensitive!
sub load_plugin {
    my ($self, $plugin_name) = @_;

    for my $plugin ($self->available_modules) {

        next unless $plugin eq $plugin_name;

        my $m = undef;
        my $command_regex = undef;

        try {
            $m = $self->load($plugin);

            # Make sure not a blank regex.
            $m = undef unless $m->can('command_regex');
            $command_regex = $m->command_regex;

            $m = undef unless defined $command_regex && $command_regex ne '';

            $m = undef unless $m->can('command_name');
            $m = undef unless $m->can('command_comment');
            $m = undef unless $m->can('acl_check');
            $m = undef unless $m->can('command_run');
        }
        catch($e) {
            $m = undef;
            warn "Plugin $plugin failed to load: $e";
        }

        next unless defined $m;

        $self->loaded_plugins->{$plugin} = $m;

        my $ver = $m->VERSION || '0.0';

        push @{$self->{plugin_regexes}}, {name => "$plugin", regex => "$command_regex"};

        warn "Plugin $plugin $ver added successfully.\n";
    }


    return 1;
}

# Case sensitive!
sub unload_plugin {
    my ($self, $plugin_name) = @_;

    my $ret = 0;

    foreach my $plugin (keys %{$self->loaded_plugins}) { 
        next unless ($plugin eq $plugin_name); # EXACT MATCH ONLY!

        $ret = $self->unload_class('Hadouken::Plugin::'.$plugin);

        warn "** UNLOADING PLUGIN $plugin - ". ($ret ? 'Success' : 'Fail'); # r is $r";

        my $x = List::MoreUtils::first_index { $_->{name} eq $plugin_name } @{$self->{plugin_regexes}};

        splice @{$self->{plugin_regexes}}, $x, 1 if $x > -1;

        delete $self->loaded_plugins->{$plugin};
    }

    return $ret;
}

sub unload_class {
    my ($self, $class) = @_;

    no strict 'refs';
    # return unless Class::Inspector->loaded( $class );

    # Flush inheritance caches
    @{$class . '::ISA'} = ();

    my $symtab = $class.'::';
    # Delete all symbols except other namespaces
    for my $symbol (keys %$symtab) {
        next if $symbol =~ /\A[^:]+::\z/;
        delete $symtab->{$symbol};
    }

    my $inc_file = join( '/', split /(?:'|::)/, $class ) . '.pm';
    delete $INC{ $inc_file };

    return 1;
}

# Load a perl module from disk and redefine symbol table
# for our plugin to have access.
sub load {
    my $self   = shift;
    my $module = shift;

    # it's safe to die here, mostly this call is eval'd.
    die "Cannot load module without a name" unless $module;
    #die("Module $module already loaded") if $self->_plugin($module);

    my $filename = $module;
    $filename =~ s{::}{/}g;
    my $file = "$filename.pm";

    $file = "./$filename.pm"         if ( -e "./$filename.pm" );
    $file = "./plugins/$filename.pm" if ( -e "./plugins/$filename.pm" );

    warn "Loading module $module from file $file\n";

    # force a reload of the file (in the event that we've already loaded it).
    no warnings 'redefine';
    delete $INC{$file};

    try { require $file } catch { die "Can't load $module: $_"; };

    no strict;
    *{"Hadouken::Plugin::$module\::new"}     = sub { 
        my $c = shift;
        my $s = {@_};
        bless $s, $c;
        return $s; 
    };

    no warnings 'redefine';
    *{"Hadouken::Plugin::$module\::send_server"} = sub { my $self = shift; $self->{Owner}->send_server_safe(@_); $self->{last_sent} = time(); };
    *{"Hadouken::Plugin\::$module\::last_sent"} = $self->_make_accessor('last_sent');
    *{"Hadouken::Plugin::$module\::asyncsock"} = sub { my $self = shift; my $client = $self->{Owner}->_asyncsock; return $client; };
    *{"Hadouken::Plugin::$module\::check_acl_bit"} = sub { my $self = shift; $self->{Owner}->isSet(@_); };

    my $m = "Hadouken::Plugin::$module"->new(
        Owner   => $self,
        Param => \@_
    );

    die "->new didn't return an object" unless ( $m and ref($m) );
    die( ref($m) . " isn't a $module" ) unless ref($m) =~ /\Q$module/;

    #$self->add_handler( $m, $module );

    return $m;
}

sub _make_accessor {
    my $self = shift;
    my $attribute = shift;
    return sub {
        my $self            = shift;
        my $new_val         = shift;
        $self->{$attribute} = $new_val if defined $new_val;
        return $self->{$attribute};
    };
}

sub stop {
    my ($self) = @_;
    return unless $self->{connected};

    if(defined $self->{con}) {
        # No reconnect.
        $self->{reconnect} = 0;

        # In our registered callback for disconnect we handle the state vars and condvar
        $self->{con}->disconnect();
    }
}

sub save_config {
    my ($self) = @_;

    my $content = $self->{conf_obj}->save_string($self->{config_hash}); #($self->{config_filename}, $conf);
    $self->{conf_update}->($content);
}

sub reload_config {
    my ($self, $content) = @_;

    my $ret = 0;

    warn "* Reloading Configuration";

    try {
        my $conf = Config::General->new(-ForceArray => 1, -String => $content, -AutoTrue => 1);
        my %config = $conf->getall;

        $self->{conf_obj} = $conf;
        $self->{config_hash} = \%config;
    }
    catch($e) {
        $ret = 1;
        warn "Error reloading config $e\n";
    }

    return $ret;
}

sub randstring {
    my $length = shift || 8;
    return join "", map { ("a".."z", 0..9)[rand 36] } 1..$length;
}

sub keyx_handler {
    my ($self, $message, $user) = @_;

    chomp $message;
    # Uncomment for debug.

    my ($command, $cbcflag, $peer_public) = $message =~ /DH1080_(INIT|FINISH)(_cbc)? (.*)/i;
    if (!$peer_public) {
        # (_cbc)? did not match, so $cbcflag is now really $peer_public. fixing that:
        $peer_public = $cbcflag;
        $cbcflag='';
    }
    if ($cbcflag eq '_cbc') {
        $self->keyx_cbc(1);
    }
    else {
        $self->keyx_cbc(0);
    }

    return 1 unless $command && $peer_public;

    my $dh1080 = undef;

    unless(defined $self->{dh1080}) {
        $self->{dh1080} = new Hadouken::DH1080;
    }

    $dh1080 = $self->{dh1080};

    # handle it.
    my $secret = $dh1080->get_shared_secret($peer_public);

    if ($secret) {
        if ($command =~ /INIT/i) {      
            my $public = $dh1080->public_key;
            my $keyx_header = 'DH1080_FINISH';
            if ($self->keyx_cbc == 1) {
                $keyx_header .= '_cbc';
            }
            
            $self->send_server_unsafe(NOTICE => $user, $keyx_header, $public);

            # $server->command("\^notice $user $keyx_header $public");
            warn "Received key from $user -- sent back our pubkey.";
        }
        else {
            warn "Negotiated key with $user";
        }
        if ($self->keyx_cbc == 1) {
            warn "CBC IS ENABLED.";
            $secret = "cbc:$secret";
        }

        my $ident = $self->{con}->nick_ident($user);
        warn "Debug: key = $secret";
        $self->_set_key( $ident, $secret );
        # $channels{$user} = 'keyx:'.$secret;
    }

}

sub readPrivateKey {
    my ($self,$file,$password) = @_;
    my $key_string;

    if (!$password) {
        open(PRIV,$file) || die "$file: $!";
        read(PRIV,$key_string, -s PRIV);
        close(PRIV);
    } else {
        $key_string = $self->decryptPEM($file,$password);
    }
    $key_string
}

sub decryptPEM {
    my ($self,$file,$password) = @_;

    my $pem = Convert::PEM->new(
        Name => 'RSA PRIVATE KEY', 
        ASN  => qq(RSAPrivateKey SEQUENCE {
        version INTEGER,
        n INTEGER,
        e INTEGER,
        d INTEGER,
        p INTEGER,
        q INTEGER,
        dp INTEGER,
        dq INTEGER,
        iqmp INTEGER
        }
        ));

    my $pkey = $pem->read(Filename => $file, Password => $password);

    $pem->encode(Content => $pkey);
}

sub start {
    my ($self) = @_;

    if($self->{connected}) {
        $self->stop();
    }

    # state variables
    $self->_set_start_time(time());
    $self->{connected} = 0;
    $self->{trivia_running} = 0;

    if(exists $self->{blowfish_key} && $self->{blowfish_key} ne '') {
        $self->_set_key( 'all', $self->{blowfish_key} );
    }

    $self->{plugin_regexes} = ();

    my $conf = $self->{config_hash};

    foreach my $plugin (keys %{$self->loaded_plugins}) { 
        my $mod = $self->_plugin($plugin);
        my $rx = $mod->command_regex;
        push @{$self->{plugin_regexes}}, {name => "$plugin", regex => $rx};

        if(exists $conf->{plugins}{$plugin}{autoload} && $conf->{plugins}{$plugin}{autoload} eq 1 ) {
            warn "* Plugin $plugin is set for autoload.";
        } else {
            $self->unload_plugin($plugin);
        }
    }

    if( $self->{private_rsa_key_filename} ne '' ) {
        my $key_string = $self->readPrivateKey($self->{private_rsa_key_filename}, $self->{private_rsa_key_password} ne '' ? $self->{private_rsa_key_password} : undef );
        $self->{_rsa} = Crypt::OpenSSL::RSA->new_private_key($key_string);
    }

    $self->{c} = AnyEvent->condvar;
    $self->{con} = AnyEvent::IRC::Client->new();

    $self->_start;
}


before 'send_server_unsafe' => sub {
    my $self = shift;

    unless(exists $self->{burst_lines}) {
        $self->{burst_lines} = 0;
    }

    $self->{burst_lines}++;

    if($self->{burst_lines} >= 10) {
        usleep($self->safe_delay);
        $self->{burst_lines} = 0;
    }
};

before 'send_server_safe' => sub {
    my $self = shift;

    unless(exists $self->{burst_lines}) {
        $self->{burst_lines} = 0;
    }

    $self->{burst_lines}++;

    if($self->{burst_lines} >= 6) {
        usleep($self->safe_delay);
        $self->{burst_lines} = 0;
    }
};

before 'send_server_long_safe' => sub {
    my $self = shift;

    unless(exists $self->{burst_lines}) {
        $self->{burst_lines} = 0;
    }

    $self->{burst_lines}++;

    if($self->{burst_lines} >= 4) {
        usleep($self->safe_delay);
        $self->{burst_lines} = 0;
    }
};


# Friendly alias for plugins.
sub send_server {&send_server_safe}


sub send_server_unsafe {
    my ($self,$command, @params) = @_;
    return unless defined $self->{con} && defined $command;

    encode ('utf8', $_  ) foreach @params;

    $self->{con}->send_srv($command,@params);
}

sub send_server_safe {
    my ($self,$command, @params) = @_;
    return unless defined $self->{con} && defined $command;

    encode ('utf8', $_  ) foreach @params;

    $self->{con}->send_srv($command,@params);
}

sub send_server_long_safe {
    my ($self,$command,@params) = @_;
    return unless defined $self->{con} && defined $command;

    $self->{con}->send_long_message("utf8",0,$command,@params);
}

sub op_user {
    my ($self, $channel, $nick, $ident) = @_;

    my $cur_channel_clean = $channel;
    $cur_channel_clean =~ s/^\#//;

    if($self->channel_mode_isset($cur_channel_clean, Hadouken::CMODE_FAST_OP)) {
        $self->send_server_unsafe( MODE => $channel, '+o', $nick);
    } else {
        my $cookie = $self->makecookie($ident,$self->{nick},$channel);
        my $test = $self->checkcookie($ident,$self->{nick},$channel,$cookie);
        $self->send_server_unsafe( MODE => $channel, '+o-b', $nick, $cookie);
    }
}

sub channel_mode_isset {
    my ($self, $channel, $mode) = @_;

    return unless defined $channel && defined $mode && length $mode;

    my $conf = $self->{config_hash};
    my $server_name = $self->{server_name};
    $channel =~ s/^\#//;

    return unless exists $conf->{server}{$server_name}{channel}{$channel};

    my $m = substr lc($mode),0,1; # Just incase they try multiple modes.
    my $x = 0;

    my %o = %{$conf->{server}{$server_name}{channel}{$channel}};

    $x = exists $o{op_admins} && $o{op_admins} eq 1 if $m eq 'o';
    $x = exists $o{op_whitelists} && $o{op_whitelists} eq 1 if $m eq 'w';
    $x = exists $o{protect_admins} && $o{protect_admins} eq 1 if $m eq 'p';
    $x = exists $o{protect_whitelists} && $o{protect_whitelists} eq 1 if $m eq 'v';
    $x = exists $o{shorten_urls} && $o{shorten_urls} eq 1 if $m eq 'u';
    $x = exists $o{aggressive} && $o{aggressive} eq 1 if $m eq 'a';
    $x = exists $o{allow_plugins} && $o{allow_plugins} eq 1 if $m eq 'z';
    $x = exists $o{fast_op} && $o{fast_op} eq 1 if $m eq 'f';
    return $x;
}

sub channel_mode_get {
    my ($self, $channel, $mode) = @_;

    return unless defined $channel && defined $mode && length $mode;

    $mode = lc($mode);
    $mode = 'owpvuazf' if $mode eq '*';

    my @modes = split //, $mode;
    my $x = $self->unique(\@modes,0);
    my $conf = $self->{config_hash};
    my $server_name = $self->{server_name};
    $channel =~ s/^\#//;

    return unless exists $conf->{server}{$server_name}{channel}{$channel};

    my %o = %{$conf->{server}{$server_name}{channel}{$channel}};

    my $mode_string = '';
    foreach my $m (@$x) {
        $mode_string .= exists $o{op_admins} && $o{op_admins} eq 1 ? '+O' : '-O' if $m eq 'o';
        $mode_string .= exists $o{op_whitelists} && $o{op_whitelists} eq 1 ? '+W' : '-W' if $m eq 'w';
        $mode_string .= exists $o{protect_admins} && $o{protect_admins} eq 1 ? '+P' : '-P' if $m eq 'p';
        $mode_string .= exists $o{protect_whitelists} && $o{protect_whitelists} eq 1 ? '+V' : '-V' if $m eq 'v';
        $mode_string .= exists $o{shorten_urls} && $o{shorten_urls} eq 1 ? '+U' : '-U' if $m eq 'u';
        $mode_string .= exists $o{aggressive} && $o{aggressive} eq 1 ? '+A' : '-A' if $m eq 'a';
        $mode_string .= exists $o{allow_plugins} && $o{allow_plugins} eq 1 ? '+Z' : '-Z' if $m eq 'z';
        $mode_string .= exists $o{fast_op} && $o{fast_op} eq 1 ? '+F' : '-F' if $m eq 'f';
    }

    return $mode_string;
}

sub channel_mode_human {
    my ($self, $channel, $mode) = @_;

    return unless defined $channel && defined $mode && length $mode;

    my @modes = unpack("(A2)*", $mode);

    foreach my $m (@modes) {
        my ($v, $k) = split //,$m;
        next unless $v eq '-' || $v eq '+';
        $self->channel_mode($channel,$k,$v);
    }

    return 1;
}

sub channel_mode {
    my ($self, $channel, $mode, $value) = @_;

    return unless defined $channel && defined $mode && defined $value && length $mode && length $value;

    $mode = lc($mode);
    $value = lc($value);

    $value = 1 if $value eq "1";
    $value = 0 if $value eq "0";
    $value = 1 if $value eq 'true';
    $value = 0 if $value eq 'false';
    $value = 1 if $value eq '+';
    $value = 0 if $value eq '-';
    $value = 1 if $value eq 'yes';
    $value = 0 if $value eq 'no';

    return unless $value == 0 || $value == 1;

# MODES:
# +O  - auto op_admins
# +W  - auto op whitelist
# +P  - protect admins
# +V  - protect whitelist
# +U  - automatically shorten urls
# +A  - aggressive mode (kick/ban instead of -o, etc)
# +Z  - allow plugins to be used in this channel
# +F  - fast op (no cookies)
    
    my $conf = $self->{config_hash};
    my $server_name = $self->{server_name};

    $channel =~ s/^\#//;

    return unless exists $conf->{server}{$server_name}{channel}{$channel};

    $conf->{server}{$server_name}{channel}{$channel}{op_admins} = $value if $mode eq 'o';
    $conf->{server}{$server_name}{channel}{$channel}{op_whitelists} = $value if $mode eq 'w';
    $conf->{server}{$server_name}{channel}{$channel}{protect_admins} = $value if $mode eq 'p';
    $conf->{server}{$server_name}{channel}{$channel}{protect_whitelists} = $value if $mode eq 'v';
    $conf->{server}{$server_name}{channel}{$channel}{shorten_urls} = $value if $mode eq 'u';
    $conf->{server}{$server_name}{channel}{$channel}{aggressive} = $value if $mode eq 'a';
    $conf->{server}{$server_name}{channel}{$channel}{allow_plugins} = $value if $mode eq 'z';
    $conf->{server}{$server_name}{channel}{$channel}{fast_op} = $value if $mode eq 'f';

    $self->save_config();

    return 1;
}

sub channel_ls {
    my ($self, $channel) = @_;

    my $conf = $self->{config_hash};
    my $server_name = $self->{server_name};
    my @channels = keys %{$conf->{server}{$server_name}{channel}};

    return @channels;
}

sub channel_add {
    my ($self, $channel) = @_;

    my $conf = $self->{config_hash};
    my $server_name = $self->{server_name};

    $channel =~ s/^\#//;

    $conf->{server}{$server_name}{channel}{$channel}{op_admins} = 1;
    $conf->{server}{$server_name}{channel}{$channel}{op_whitelists} = 1;
    $conf->{server}{$server_name}{channel}{$channel}{protect_admins} = 0;
    $conf->{server}{$server_name}{channel}{$channel}{protect_whitelists} = 0;
    $conf->{server}{$server_name}{channel}{$channel}{shorten_urls} = 0;
    $conf->{server}{$server_name}{channel}{$channel}{aggressive} = 0;
    $conf->{server}{$server_name}{channel}{$channel}{allow_plugins} = 1;
    $conf->{server}{$server_name}{channel}{$channel}{fast_op} = 0;

    $self->save_config();

    $self->send_server_unsafe (JOIN => '#'.$channel);

    return 1;
}


sub channel_del {
    my ($self, $channel) = @_;

    my $conf = $self->{config_hash};
    my $server_name = $self->{server_name};

    $channel =~ s/^\#//;

    if(exists $conf->{server}{$server_name}{channel}{$channel}) {
        delete $conf->{server}{$server_name}{channel}{$channel};
    }

    $self->save_config();
    $self->send_server_unsafe (PART => '#'.$channel);

    return 1;
}

# ident,quote,channel,time
#
# $row is an array ref.
sub write_quote_row {
    my ($self, $row) = @_;

    if(defined $self->{_rsa}) {
        # The second param in encode_base64 removes line endings
        my $encrypted = MIME::Base64::encode_base64($self->{_rsa}->encrypt($row->[1]),''); 

        $row->[1] = "$encrypted";
    }

    push(@{$self->{quotesdb}},$row);
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

sub flatten {
    my $self = shift;
    my ($array) = $self->_prepare(@_);

    my $cb;
    $cb = sub {
        my $result = [];
        foreach (@{$_[0]}) {
            if (ref $_ eq 'ARRAY') {
                push @$result, @{$cb->($_)};
            }
            else {
                push @$result, $_;
            }
        }
        return $result;
    };

    my $result = $cb->($array);

    return $self->_finalize($result);
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

sub to_array {
    my $self = shift;
    my ($list) = $self->_prepare(@_);

    return [values %$list] if ref $list eq 'HASH';

    return [$list] unless ref $list eq 'ARRAY';

    return [@$list];
}

sub forEach {
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

sub select {
    my $self = shift;
    my ($list, $iterator, $context) = $self->_prepare(@_);

    my $result = [grep { $iterator->($_) } @$list];

    $self->_finalize($result);
}

sub size {
    my $self = shift;
    my ($list) = $self->_prepare(@_);

    return scalar @$list if ref $list eq 'ARRAY';

    return scalar keys %$list if ref $list eq 'HASH';

    return 1;
}

sub unique {
    my $self = shift;
    my ($array, $is_sorted) = $self->_prepare(@_);

    return [List::MoreUtils::uniq(@$array)] unless $is_sorted;

    my $new_array = [shift @$array];
    foreach (@$array) {
        push @$new_array, $_ unless $_ eq $new_array->[-1];
    }

    return $new_array;
}

sub blacklisted {
    my ($self, $who) = @_;
    
    my $bl = _->detect(\@{$self->{blacklistdb}}, sub { 
            my $entry = '';
            $entry = $_->[0] eq '*!*' ? '' : '*!*'; # : ''; #.$_->[0].'@'.$_->[1] : ;
            $entry .= $_->[0].'@'.$_->[1];

            if($self->matches_mask($entry, $who)) {
                return $who;
            }
        });

    if(defined $bl && length $bl) {
        return 1;
    }

    return 0;
}

sub whitelisted {
    my ($self, $who) = @_;
    
    my $wl = _->detect(\@{$self->{whitelistdb}}, sub { 
            my $entry = '';
            $entry = $_->[0] eq '*!*' ? '' : '*!*'; # : ''; #.$_->[0].'@'.$_->[1] : ;
            $entry .= $_->[0].'@'.$_->[1];

            if($self->matches_mask($entry, $who)) {
                return $who;
            }
        });

    if(defined $wl && length $wl) {
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

    my $admin = _->detect(\@{$self->{adminsdb}}, sub { 
            my $entry = '';
            $entry = $_->[0] eq '*!*' ? '' : '*!*'; # : ''; #.$_->[0].'@'.$_->[1] : ;
            $entry .= $_->[0].'@'.$_->[1];


            if($self->matches_mask($entry, $who)) {
                return $who;
            }
        });

    if(defined $admin && length $admin) {
        return 1;
    }

    return 0;
}

sub is_bot {
    my ($self, $who) = @_;

    my $bot = _->detect(\@{$self->{botsdb}}, sub { 
            my $entry = '';
            $entry = $_->[0] eq '*!*' ? '' : '*!*'; # : ''; #.$_->[0].'@'.$_->[1] : ;
            $entry .= $_->[0].'@'.$_->[1];

            if($self->matches_mask($entry, $who)) {
                return $who;
            }
        });

    if(defined $bot && length $bot) {
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

    push(@{$self->{adminsdb}}, @admin_row);

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

    push(@{$self->{whitelistdb}}, @whitelist_row);

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

    push(@{$self->{blacklistdb}}, @blacklist_row);

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


sub _has_color {
    my $self = shift;
    my ($string) = @_;
    return if !defined $string;
    return 1 if $string =~ /[\x03\x04\x1B]/;
    return;
}

sub _has_formatting {
    my $self = shift;
    my ($string) = @_;
    return if !defined $string;
    return 1 if $string =~/[\x02\x1f\x16\x1d\x11\x06]/;
    return;
}

sub _strip_color {
    my ($self, $string) = @_;

    return unless defined $string;

    $string =~ s/\x03(?:,\d{1,2}|\d{1,2}(?:,\d{1,2})?)?//g;
    $string =~ s/\x04[0-9a-fA-F]{0,6}//g;
    $string =~ s/\x1B\[.*?[\x00-\x1F\x40-\x7E]//g;
    $string =~ s/\x0f//g if !$self->_has_formatting($string);
    return $string;
}

sub _filter_colors {
    my $self = shift;
    my ($line) = @_;
    $line =~ s/\x1B\[.*?[\x00-\x1F\x40-\x7E]//g;
    $line =~ s/\x03\d\d?(?:,\d\d?)?//g;
    $line =~ s/[\x03\x16\x02\x1f\x0f]//g;
    return $line;
}

sub _strip_formatting {
    my $self = shift;
    my ($string) = @_;
    return if !defined $string;
    $string =~ s/[\x02\x1f\x16\x1d\x11\x06]//g;
    $string =~ s/\x0f//g if !$self->_has_color($string);
    return $string;
}

sub _decode_irc {
    my $self = shift;
    my ($line) = @_;
    my $utf8 = guess_encoding($line, 'utf8');
    return ref $utf8 ? decode('utf8', $line) : decode('cp1252', $line);
}

sub hexdump {
    my $self = shift;
    my ($label,$data);
    if (scalar(@_) == 2) {
        $label = shift;
    }
    $data = shift;

    print "$label:\n" if ($label);
    my @bytes = split(//, $data);
    my $col = 0;
    my $buffer = '';
    for (my $i = 0; $i < scalar(@bytes); $i++) {
        my $char    = sprintf("%02x", unpack("C", $bytes[$i]));
        my $escaped = unpack("C", $bytes[$i]);
        if ($escaped < 20 || $escaped > 126) {
            $escaped = ".";
        }
        else {
            $escaped = chr($escaped);
        }

        $buffer .= $escaped;
        print "$char ";
        $col++;

        print "  " if $col == 8;
        if ($col == 16) {
            $buffer .= " " until length $buffer == 16;
            print "  |$buffer|\n";
            $buffer = "";
            $col    = 0;
        }
    }
    while ($col < 16) {
        print "   ";
        $col++;
        print "  " if $col == 8;
        if ($col == 16) {
            $buffer .= " " until length $buffer == 16;
            print "  |$buffer|\n";
            $buffer = "";
        }
    }
    if (length $buffer) {
        print "|$buffer|\n";
    }
}

sub jsonify {
    my $self = shift;
    my $hashref = decode_json( encode("utf8", shift) );
    return $hashref;
}

sub encode_jsonify {
    my $self = shift;
    my $json = encode_json(encode("utf8",shift));
    return $json;
}

sub fetch_json {
    my $self = shift;
    my $url = shift;
    my $json;

    try {
        my $response = $self->_webclient->get($url);
        $json = $self->jsonify($response->content);
    } catch($e) {
        warn "Error in fetch_json $e\n";
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
    $self->{botsdb} = ();

    #my $redis = Redis->new;
   
    if(-e $self->{ownerdir}.'/../data/wotmate.txt') {
        open(my $fh, $self->{ownerdir}.'/../data/wotmate.txt') or die $!;
        chomp(my @wots = <$fh>);
        $self->{wots} = \@wots;
        close $fh;
    }

    $self->{geoip} = Geo::IP->open($self->{ownerdir}.'/../data/geoip/GeoIPCity.dat') or die $!;

    my $after_parse_cb = sub { 
        my ($csv, $row) = @_;

        if( exists $self->{_rsa} ) {
            my $therow = $row->[1];

            try {
                $therow = MIME::Base64::decode_base64($row->[1]);
                $therow = $self->{_rsa}->decrypt($therow);
            }
            catch($e) {
                $therow = $row->[1];
            }
            $row->[1] = $therow;
        }
    };

    my $tieobj = tie @{$self->{quotesdb}}, 'Tie::Array::CSV', $self->{ownerdir}.'/../data/quotes.txt', 
    {  memory => 20_000_000,  
        text_csv => { binary => 1, 
            callbacks => { after_parse => $after_parse_cb } 
        } 
    } or die $!;

    #my $tie_file = sub {
    #    my ($array, $tieName, $filename);
    #    return tie @$array, $tieName, $filename;
    #}

    #my $datadir = $self->{ownerdir}.'/../data';

    #my $tieadminobj     =   $tie_file->($self->{adminsdb},    'Tie::Array::CSV', "$datadir/admins.txt");
    #my $tiewhitelistobj =   $tie_file->($self->{whitelistdb}, 'Tie::Array::CSV', "$datadir/whitelist.txt");
    #my $tieblacklistobj =   $tie_file->($self->{blacklistdb}, 'Tie::Array::CSV', "$datadir/blacklist.txt");

    #my $hc = Hadouken::Configuration->new;

    #$self->{redis} = Redis->new;

    #tie my @my_list, 'Redis::List', 'list_name3';

    my $tieadminobj = tie @{$self->{adminsdb}}, 'Tie::Array::CSV', $self->{ownerdir}.'/../data/admins.txt' or die $!;

    my $tiebotobj = tie @{$self->{botsdb}}, 'Tie::Array::CSV', $self->{ownerdir}.'/../data/bots.txt' or die $!;

    #@crap = map { [@$_] } @{$self->{adminsdb}};
    #@my_list = @{$self->{adminsdb}};

    #foreach my $crap (@{$self->{adminsdb}}) {

    #    push(@my_list,@{$crap});
    #}

    #print Dumper(@my_list);
    #exit;


    my $tiewhitelistobj = tie @{$self->{whitelistdb}}, 'Tie::Array::CSV', $self->{ownerdir}.'/../data/whitelist.txt' or die $!;

    my $tieblacklistobj = tie @{$self->{blacklistdb}}, 'Tie::Array::CSV', $self->{ownerdir}.'/../data/blacklist.txt' or die $!;

    # Add ourselves into the db if we arent in already!
    unless ($self->is_admin($self->{admin})) {
        my ($nick,$host) = split(/@/,$self->{admin});
        my @admin_row = [$nick, $host, '*', time()];
        push(@{$self->{adminsdb}}, @admin_row);
    }

    my $func_flags = sub {
        my ($who, $message, $channel, $channel_list) = @_;

        { use integer;

            my $userFlags = pack('b8','00001100');

            $userFlags = $self->addFlag($userFlags, BIT_ADMIN) if($self->is_admin($who));
            $userFlags = $self->addFlag($userFlags, BIT_BLACKLIST) if($self->blacklisted($who));
            $userFlags = $self->addFlag($userFlags, BIT_WHITELIST) if($self->whitelisted($who));
            $userFlags = $self->addFlag($userFlags, BIT_BOT) if($self->is_bot($who));

            if(defined $channel_list) {
                my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

                if(exists $channel_list->{$nickname}) {
                    {
                        use experimental qw/smartmatch/;

                        $userFlags = $self->addFlag($userFlags, BIT_OP) if(/o$/ ~~ $channel_list->{$nickname});
                        $userFlags = $self->addFlag($userFlags, BIT_VOICE) if(/v$/ ~~ $channel_list->{$nickname});
                    }
                }
            }

            return $userFlags;
        }
    };

    #
    # menace - men·ace noun: a person or thing that is likely to cause harm; a threat or danger.
    #
    # redid ACL so we can avoid menace(s).

    my $plugin_acl_func = _->wrap(
        $func_flags => sub {
            my $func = shift;
            my ($who, $message, $channel, $channel_list) = @_;

            { use integer;

                my $flags = $func->(@_);

                my %accessControlEntry = (
                    "permissions" => $flags, 
                    "who" => $who, 
                    "channel" => $channel, 
                    "message" => $message
                );

                return %accessControlEntry;
            }
        }
    );


    my $passive_access = _->wrap(
        $func_flags => sub {
            my $func = shift;
            my ($who, $message, $channel, $channel_list) = @_;

            { use integer;

                my $flags = $func->(@_);

                return 1 if($self->isSet($flags,BIT_ADMIN) || $self->isSet($flags,BIT_WHITELIST));

                return 0 if($self->isSet($flags,BIT_BLACKLIST));

                # We check blacklist first before checking these. ORDER COUNTS.
                return 1 if($self->isSet($flags,BIT_OP) || $self->isSet($flags,BIT_VOICE));

                return 0;
            }
        }
    );

    my $op_access = _->wrap(
        $func_flags => sub {
            my $func = shift;
            my ($who, $message, $channel, $channel_list) = @_;

            { use integer;

                my $flags = $func->(@_);

                return 1 if($self->isSet($flags,BIT_ADMIN) || $self->isSet($flags,BIT_WHITELIST));

                return 0 if($self->isSet($flags,BIT_BLACKLIST));

                # We check blacklist first before checking these. ORDER COUNTS.
                return 1 if($self->isSet($flags,BIT_OP));

                return 0;
            }
        }
    );

    my $restrictive_access = _->wrap(
        $func_flags => sub {
            my $func = shift;
            my ($who, $message, $channel, $channel_list) = @_;

            { use integer;

                my $flags = $func->(@_);
                return 1 if($self->isSet($flags,BIT_ADMIN) || $self->isSet($flags,BIT_WHITELIST));
                return 0;
            }
        }
    );

    my $admin_access = _->wrap(
        $func_flags => sub {
            my $func = shift;
            my ($who, $message, $channel, $channel_list) = @_;

            { use integer;

                my $flags = $func->(@_);
                return 1 if($self->isSet($flags,BIT_ADMIN));
                return 0;
            }
        }
    );

    my $whitelist_access = _->wrap(
        $func_flags => sub {
            my $func = shift;
            my ($who, $message, $channel, $channel_list) = @_;

            { use integer;

                my $flags = $func->(@_);
                return 1 if($self->isSet($flags,BIT_ADMIN) || $self->isSet($flags,BIT_WHITELIST));
                return 0;
            }
        }
    );

    my $all_access_except_blacklist = _->wrap(
        $func_flags => sub {
            my $func = shift;
            my ($who, $message, $channel, $channel_list) = @_;

            { use integer;

                my $flags = $func->(@_);
                return 0 if($self->isSet($flags,BIT_BLACKLIST));
                return 1;
            }
        }
    );

    $self->add_func(name => 'trivia',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

            return unless defined $channel;

            my (undef,$cmd, $arg) = split(/ /, $message, 3);

            return unless defined $cmd && length $cmd;

            $cmd = lc($cmd);

            if($cmd eq 'start') {
                $self->_start_trivia($channel);
            } elsif($cmd eq 'stop') {
                $self->_stop_trivia;
            }

            return 1;
        },
        acl => $admin_access
    );


    $self->add_func(name => 'powerup',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
            my $ref_modes = $self->{con}->nick_modes ($channel, $nickname);

            return unless defined $ref_modes;

            unless($ref_modes->{'o'}) {
                $self->op_user($channel,$nickname,$ident);

                # $self->send_server_unsafe( MODE => $channel, '+o', $nickname);
            }

            return 1;
        },
        acl => $admin_access
    );

    $self->add_func(name => 'raw',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
            my ($cmd, $arg) = split(/ /, $message, 2);

            return unless defined $arg;

            my @send_params = split(/ /, $arg);
            return unless($#send_params >= 0);
            my $send_command = shift(@send_params);

            warn "Send command $send_command\n";
            warn "Params: ".join("\t",@send_params)."\n";

            $self->send_server_unsafe ($send_command, @send_params);

            return 1;
        },
        acl => $admin_access,
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
                @found = List::MoreUtils::indexes { lc($_->[1]) =~ lc($arg) && $_->[2] eq $channel } @{$self->{quotesdb}};
            } else {

                @found = List::MoreUtils::indexes { 
                    $arg ne '' 
                    ? (($_->[2] eq $channel) && lc($_->[1]) =~ lc($arg)) && (lc($_->[0]) =~ lc($creator)) 
                    : lc($_->[0]) =~ lc($creator) && $_->[2] eq $channel 
                } @{$self->{quotesdb}};

                #if(defined $arg && $arg ne '') {
                #   @found = List::MoreUtils::indexes { (lc($_->[1]) =~ lc($arg)) && (lc($_->[0]) =~ lc($creator)) } @{$self->{quotesdb}};
                #} else {
                #   @found = List::MoreUtils::indexes { lc($_->[0]) =~ lc($creator) } @{$self->{quotesdb}};
                #}
            }

            unless(@found) {
                $self->send_server_unsafe (PRIVMSG => $channel, 'nothing found in quotes!');
                return;
            }

            my $found_count = scalar @found;

            unless($found_count > 0) {
                $self->send_server_unsafe (PRIVMSG => $channel, 'nothing found in quotes!');
                return;
            }

            my $si = String::IRC->new($found_count)->bold;

            $self->send_server_unsafe (PRIVMSG => $channel, 'found '.$si.' quotes!');

            my $limit = 0;
            foreach my $z (@found) {

                $limit++;
                last if($limit > $self->quote_limit);

                my @the_quote = $self->{quotesdb}[$z];

                #my ($q_mode_map,$q_nickname,$q_ident) = $self->{con}->split_nick_mode($the_quote[0][0]);
                #my $epoch_string = strftime "%a %b%e %H:%M:%S %Y", localtime($the_quote[0][3]);

                my $hightlighted = $the_quote[0][1];

                my $highlight_sub = sub {
                    return String::IRC->new($_[0])->bold;
                };

                $hightlighted =~ s/($arg)/$highlight_sub->($1)/ge;
                $self->send_server_unsafe (PRIVMSG => $channel, '['.int($z + 1).'] '.$hightlighted); # - added by '.$q_nickname.' on '.$epoch_string);
            }

            return 1;
        },
        acl => $all_access_except_blacklist,
    );

    $self->add_func(name => 'rq',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
            my @this_channel_only;

            @this_channel_only = List::MoreUtils::indexes { $_->[2] eq $channel } @{$self->{quotesdb}};

            my $quote_count = scalar @this_channel_only;

            return unless($quote_count > 0);

            my $rand_idx = int(rand($quote_count));
            my @rand_quote = $self->{quotesdb}[$this_channel_only[$rand_idx]];
            $self->send_server_unsafe (PRIVMSG => $channel, '['.int($this_channel_only[$rand_idx] + 1).'] '.$rand_quote[0][1]);

            return 1;
        },
        acl => $all_access_except_blacklist,
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

            $self->send_server_unsafe (PRIVMSG => $channel, 'Quote #'.$arg.' has been deleted.');

            return 1;
        },
        acl => $admin_access,
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

            while($arg =~ /$RE{num}{int}{-sep => ""}{-keep}/g) {
                push(@real_indexes,int($1 - 1));
            }

            my $x = _->unique(\@real_indexes,1);

            my $search_count = _->size($x);
            my $sent = 0;

            foreach my $j (@$x) {
                next unless $j >=0 && $j < $quote_count;

                my @curr_quote = $self->{quotesdb}[$j]; # Don't dereference this.
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

                #only show for this channel!
                next unless $col_channel eq $channel;
                next if $sent >= $self->quote_limit;

                $sent++;

                my ($q_mode_map,$q_nickname,$q_ident) = $self->{con}->split_nick_mode($col_who);
                my $epoch_string = strftime "%a %b%e %H:%M:%S %Y", localtime($col_time);

                my $si1 = String::IRC->new('[')->black;
                my $si2 = String::IRC->new(int($j+1))->red('black')->bold;
                my $si3 = String::IRC->new('/'.$quote_count)->yellow('black');
                my $si4 = String::IRC->new('] '.$col_quote.' - added by '.$q_nickname.' on '.$epoch_string)->black;

                my $msg = "$si1$si2$si3$si4";
                my $no_color = "[".int($j+1)."/".$quote_count."] $col_quote - added by $q_nickname on $epoch_string";

                $self->send_server_unsafe (PRIVMSG => $channel, $no_color); #$si1.''.$si2.''.$si3.''.$si4
            }

            return 1;
        },
        acl => $all_access_except_blacklist,
    );


    $self->add_func(name => 'lq',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
            my @quote_indexes;

            @quote_indexes = List::MoreUtils::indexes { $_->[2] eq $channel } @{$self->{quotesdb}};

            return unless(@quote_indexes);

            my $channel_quote_count = scalar @quote_indexes;

            if ($channel_quote_count > 0) {
                my @last_quote = $self->{quotesdb}[$quote_indexes[int($channel_quote_count - 1)]];
                my ($q_mode_map,$q_nickname,$q_ident) = $self->{con}->split_nick_mode($last_quote[0][0]);
                my $epoch_string = strftime "%a %b%e %H:%M:%S %Y", localtime($last_quote[0][3]);

                $self->send_server_unsafe (PRIVMSG => $channel, '['.int($quote_indexes[$channel_quote_count - 1] + 1).'] '.$last_quote[0][1].' - added by '.$q_nickname.' on '.$epoch_string);
            }

            return 1;
        },
        acl => $all_access_except_blacklist,
    );

    $self->add_func(name => 'aq',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
            my ($cmd, $arg) = split(/ /,$message, 2);

            return unless (defined $arg) && (length $arg);

            my @quote_row = [$ident, $arg, $channel, time()];

            $self->write_quote_row(@quote_row);

            my $quote_count = scalar @{$self->{quotesdb}};

            $self->{con}->send_srv (PRIVMSG => $channel, 'Quote #'.$quote_count.' added by '.$nickname.'.');

            return 1;
        },
        acl => $whitelist_access,
    );

    $self->add_func(name => 'commands',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

            #my $cmd_names = _->pluck(\@commands, 'name');

            my @copy = @commands;
            my $iter = List::MoreUtils::natatime 2, @copy;
            my $si1 = String::IRC->new('Available Commands:')->bold;

            #$self->send_server_unsafe (NOTICE => $nickname, $si1);
            $self->send_server_unsafe (PRIVMSG => $nickname, $si1);
            #$self->send_server_long_safe ("PRIVMSG\001ACTION", $nickname, $si1);
            # $self->send_server_unsafe (PRIVMSG => $nickname, $si1);

            while( my @tmp = $iter->() ) {
                my $command_summary = '';
                foreach my $c (@tmp) {
                    if($c->{require_admin}) {
                        next unless $self->is_admin($who);
                    }

                    next unless(defined($c->{acl}));

                    next 
                    unless 
                    defined($c->{name}) && $c->{name} ne '' && 
                    defined($c->{comment}) && $c->{comment} ne '';

                    # Only list the commands this user passes for that commands ACL definition.
                    my $acl_ret = $c->{acl}->($who, $message, $channel || undef, $channel_list || undef);

                    next unless $acl_ret;

                    my $si = String::IRC->new($c->{name})->bold;
                    $command_summary .= '['.$si.'] -> '.$c->{comment}."  ";
                }

                $self->send_server_unsafe (PRIVMSG => $nickname, $command_summary);
                #$self->send_server_unsafe (NOTICE => $nickname, $command_summary);
                #$self->send_server_long_safe ("PRIVMSG\001ACTION", $nickname, $command_summary);
                #$self->send_server_unsafe (PRIVMSG => $nickname, $command_summary);
                undef $command_summary;
            }
            undef $iter;

            return 1;
        },
        acl => $all_access_except_blacklist,
    );


    # This is for all users(except blacklisted), to see which plugins they have access to.
    #
    $self->add_func(name => 'plugins',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

            try { # Plugins can be unpredictable.

                my $pcount = scalar keys %{$self->loaded_plugins};

                if(defined $pcount && $pcount < 1) {
                    my $si1 = String::IRC->new('No plugins are available for you!')->bold;
                    #$self->send_server_unsafe (NOTICE => $nickname, $si1);
                    $self->send_server_unsafe (PRIVMSG => $nickname, $si1);
                    return 1;
                }   

                my $si1 = String::IRC->new('Available Plugins:')->bold;
                $self->send_server_unsafe (PRIVMSG => $nickname, $si1);

                foreach my $plugin (keys %{$self->loaded_plugins}) { 
                    my $command_summary = '';
                    my $p = $self->_plugin($plugin);

                    my $name = $p->command_name;
                    my $comment = $p->command_comment || '';
                    my $ver = $p->VERSION || '0.0';

                    my $si = String::IRC->new($name)->bold;
                    $command_summary .= '['.$si.'] '.$ver.' -> '.$comment." ";

                    $self->send_server_unsafe (PRIVMSG => $nickname, $command_summary);
                }
            }
            catch($e) {
                warn "Error in command \'plugins\' $e\n";
            }

            return 1;
        },
        acl => $all_access_except_blacklist,
    );


    $self->add_func(name => 'admin',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

            my (undef,$cmd, $arg) = split(/ /, $message, 3);

            return unless defined $cmd && length $cmd;

            #return unless defined $arg && defined $cmd && length $cmd && length $arg;

            $cmd = lc($cmd);

            if($cmd eq 'add') {
                return unless defined $arg;
                my $add_ret = $self->admin_add($who, $arg);

                if($add_ret) {
                    my $out_msg = "[admin] $arg added - > by $nickname";
                    my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg); #, $self->{keys}->[0] );
                    $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                }
            } 
            elsif($cmd eq 'delete' || $cmd eq 'del' || $cmd eq 'remove' || $cmd eq 'rem' || $cmd eq 'rm') {
                return unless defined $arg;
                my $del_ret = $self->admin_delete($who, $arg);

                if($del_ret) {
                    my $out_msg = "[admin] $arg deleted - > by $nickname";
                    my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who,$out_msg ); #, $self->{keys}->[0] );
                    $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                } 
            }
            elsif($cmd eq 'list' || $cmd eq 'ls') {
                #my $owner = '*!*dek@butche.red';
                my $owner = $self->normalize_mask($self->{admin});
                warn "* ADMIN LIST $owner";
                warn "* ADMIN LIST $who";
                #if($self->matches_mask($owner,$who)) {
                for my $admin_row (@{$self->{adminsdb}}) {
                    my $entry = $admin_row->[0];
                    $entry .= " ".$admin_row->[1];
                    $entry .= " created ";
                    $entry .= scalar(gmtime($admin_row->[3]));
                    $entry .= " added by ".$admin_row->[4] if defined $admin_row->[4];
                    my $out_msg = "[admin] $entry";

                    my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg ); #, $self->{keys}->[0] );
                    $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                    #$self->send_server_unsafe (PRIVMSG => $nickname, $entry);
                }
                #}
            }
            elsif($cmd eq 'grep') {

                return unless defined $arg;

                my $owner = $self->normalize_mask($self->{admin});
                # warn "* ADMIN LIST $owner";
                # warn "* ADMIN LIST $who";

                #if($self->matches_mask($owner,$who)) {
                my @matches = grep { /$arg/ } map { $_->[0].'@'.$_->[1] } @{$self->{adminsdb}};
                #warn Dumper(@matches);
                for my $admin_row (@matches) {
                    my $out_msg = "[admin] $admin_row";
                    my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg ); #, $self->{keys}->[0] );
                    $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                }
                #}
            }
            elsif($cmd eq 'key') {
                return unless defined $arg;

                my $conf = $self->{config_hash};
                $conf->{keys}{$who}{key} = $arg;

                $self->save_config();

                $self->_set_key( $who, $arg );

                #my $content = $self->{conf_obj}->save_string(); #($self->{config_filename}, $conf);
                #$self->{conf_update}->($content);
            } elsif($cmd eq 'reload') {
                my $out_msg = "[admin] reloading!";
                my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg ); #, $self->{keys}->[0] );
                $self->send_server_unsafe (PRIVMSG => $nickname, $msg);

                $self->{reload_update}->();
            }
            return 1;
        },
        acl => $admin_access,
    );

    $self->add_func(name => 'whitelist',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

            my (undef,$cmd, $arg) = split(/ /, $message, 3);

            return unless defined $cmd && length $cmd;

            #return unless defined $arg && defined $cmd && length $cmd && length $arg;

            $cmd = lc($cmd);

            if($cmd eq 'add') {
                return unless defined $arg;
                my $add_ret = $self->whitelist_add($who, $arg);

                if($add_ret) {
                    my $out_msg = "[whitelist] $arg added - > by $nickname";
                    my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );
                    $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                }
            } 
            elsif($cmd eq 'delete' || $cmd eq 'del' || $cmd eq 'remove' || $cmd eq 'rem' || $cmd eq 'rm') {
                return unless defined $arg;
                my $del_ret = $self->whitelist_delete($who, $arg);

                if($del_ret) {
                    my $out_msg = "[whitelist] $arg deleted - > by $nickname";
                    my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );
                    $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                } 
            }
            elsif($cmd eq 'list' || $cmd eq 'ls') {
                #my $owner = '*!*dek@butche.red';
                my $owner = $self->normalize_mask($self->{admin});
                warn "* WHITELIST LIST $owner";
                warn "* WHITELIST LIST $who";
                #if($self->matches_mask($owner,$who)) {
                for my $wl_row (@{$self->{whitelistdb}}) {
                    my $entry = $wl_row->[0];
                    $entry .= " ".$wl_row->[1];
                    $entry .= " created ";
                    $entry .= scalar(gmtime($wl_row->[3]));
                    $entry .= " added by ".$wl_row->[4] if defined $wl_row->[4];
                    my $out_msg = "[whitelist] $entry";

                    my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );
                    $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                    #$self->send_server_unsafe (PRIVMSG => $nickname, $entry);
                }
                #}
            }

            return 1;
        },
        acl => $admin_access,
    );

    $self->add_func(name => 'blacklist',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

            my (undef,$cmd, $arg) = split(/ /, $message, 3);

            return unless defined $cmd && length $cmd;

            #return unless defined $arg && defined $cmd && length $cmd && length $arg;

            $cmd = lc($cmd);

            if($cmd eq 'add') {
                return unless defined $arg;
                my $add_ret = $self->blacklist_add($who, $arg);

                if($add_ret) {
                    my $out_msg = "[blacklist] $arg added - > by $nickname";
                    my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );
                    $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                }
            } 
            elsif($cmd eq 'delete' || $cmd eq 'del' || $cmd eq 'remove' || $cmd eq 'rem' || $cmd eq 'rm') {
                return unless defined $arg;
                my $del_ret = $self->blacklist_delete($who, $arg);

                if($del_ret) {
                    my $out_msg = "[blacklist] $arg deleted - > by $nickname";
                    my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );
                    $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                } 
            }
            elsif($cmd eq 'list' || $cmd eq 'ls') {
                #my $owner = '*!*dek@butche.red';
                my $owner = $self->normalize_mask($self->{admin});
                #warn "* BLACKLIST LIST $owner";
                #warn "* BLACKLIST LIST $who";
                if($self->matches_mask($owner,$who)) {
                    for my $wl_row (@{$self->{blacklistdb}}) {
                        my $entry = $wl_row->[0];
                        $entry .= " ".$wl_row->[1];
                        $entry .= " created ";
                        $entry .= scalar(gmtime($wl_row->[3]));
                        $entry .= " added by ".$wl_row->[4] if defined $wl_row->[4];
                        my $out_msg = "[blacklist] $entry";

                        my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );
                        $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                        #$self->send_server_unsafe (PRIVMSG => $nickname, $entry);
                    }
                }
            }

            return 1;
        },
        acl => $admin_access,
    );


    $self->add_func(name => 'channel',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

            my (undef,$cmd, $arg) = split(/ /, $message, 3);

            return unless defined $cmd && length $cmd;

            $cmd = lc($cmd);

            if($cmd eq 'mode') {

                my ($chan_name, $mode_name, $mode_value) = split(/ /, $arg, 3);

                return unless ((defined $chan_name) && ($self->{con}->is_channel_name($chan_name)));

                if(defined $mode_value && length $mode_value) {
                    # Set mode.
                    $self->channel_mode($chan_name,$mode_name,$mode_value);

                    my $current_mode = $self->channel_mode_get($chan_name,$mode_name);
                    my $out_msg = "[channel] mode for $chan_name set to $current_mode - > by $nickname";
                    my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );
                    $self->send_server_unsafe (PRIVMSG => $nickname, $msg);

                    return 1;

                } else {
                    if(defined $mode_name && length $mode_name && length($mode_name) gt 1) { # Probably trying to set mode.
                        $self->channel_mode_human($chan_name,$mode_name);

                        my $current_mode = $self->channel_mode_get($chan_name,$mode_name);
                        my $out_msg = "[channel] mode for $chan_name set to $current_mode - > by $nickname";
                        my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );
                        $self->send_server_unsafe (PRIVMSG => $nickname, $msg);

                    } else { # Trying to get singular mode value perhaps?

                        # Return current mode value.
                        my $current_mode = $self->channel_mode_get($chan_name, defined $mode_name && length $mode_name ? $mode_name : '*');
                        my $out_msg = "[channel] $chan_name: $current_mode";
                        my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );
                        $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                    }

                    return 1;
                }

            }
            elsif($cmd eq 'add') {
                return unless ((defined $arg) && ($self->{con}->is_channel_name($arg)));

                $self->channel_add($arg);

                return 1;
            } 
            elsif($cmd eq 'delete' || $cmd eq 'del' || $cmd eq 'remove' || $cmd eq 'rem' || $cmd eq 'rm') {
                return unless ((defined $arg) && ($self->{con}->is_channel_name($arg)));

                $self->channel_del($arg);

                return 1;
            }
            elsif($cmd eq 'list' || $cmd eq 'ls') {
                my $owner = $self->normalize_mask($self->{admin});

                unless($self->matches_mask($owner,$who)) {
                    warn "* $nickname is listing channels";
                } #else {
                warn "* Owner is listing channels.";

                my @chans = $self->channel_ls;

                for my $ch (@chans) {
                    my $current_mode = $self->channel_mode_get($ch, '*');
                    my $out_msg = "[channel] \#$ch $current_mode";
                    my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );
                    $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                }

#                    for my $admin_row (@{$self->{adminsdb}}) {
#                        my $entry = $admin_row->[0];
#                        $entry .= " ".$admin_row->[1];
#                        $entry .= " created ";
#                        $entry .= scalar(gmtime($admin_row->[3]));
#                        $entry .= " added by ".$admin_row->[4] if defined $admin_row->[4];
#                        my $out_msg = "[admin] $entry";
                #
#                        my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );
#                        $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
#                        #$self->send_server_unsafe (PRIVMSG => $nickname, $entry);
#                    }
                #}
            }

            return 1;
        },
        acl => $admin_access,
    );


    $self->add_func(name => 'plugin',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

            my ($cmd,$name, $arg) = split(/ /, $message, 3);

            return unless defined $arg && defined $name && length $arg && length $name;

            $arg = lc($arg);

            if($arg eq 'load') {
                if($name eq '*' || $name eq 'all') {
                    for my $p ($self->available_modules) {
                        my $added_ok = $self->load_plugin($p);

                        next unless ($added_ok);
                        my $out_msg = "[plugin] $p loaded - > by $nickname";

                        my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );

                        $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                    }
                } else {
                    my $plugin_name = '';
                    if ( defined($plugin_name = List::MoreUtils::first_value { $name eq $_ } $self->available_modules) ) {

                        return if exists $self->loaded_plugins->{$plugin_name};

                        my $added_ok = $self->load_plugin($plugin_name);

                        return unless ($added_ok);
                        my $out_msg = "[plugin] $name loaded - > by $nickname";

                        my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );

                        $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                    }
                }
            } elsif($arg eq 'unload') {
                if($name eq '*' || $name eq 'all') {
                    # We do this because of central installed and locally installed modules.
                    my @avail = $self->available_modules();
                    my $x = _->unique(\@avail,0);

                    for my $p (@avail) {
                        my $unload_ok = $self->unload_plugin($p);

                        next unless ($unload_ok);

                        my $out_msg = "[plugin] $p unloaded - > by $nickname";

                        my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );

                        $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                    }
                } else {
                    my $plugin_name = '';
                    if ( defined($plugin_name = List::MoreUtils::first_value { $name eq $_ } $self->available_modules) ) {

                        my $unloaded_ok = $self->unload_plugin($plugin_name);

                        return unless ($unloaded_ok);
                        my $out_msg = "[plugin] $name unloaded - > by $nickname";

                        my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );

                        $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                    }
                }
            } elsif($arg eq 'status') {
                if($name eq '*' || $name eq 'all') {
                    #my $si1 = String::IRC->new('All Available Plugins:')->bold;
                    #$self->send_server_unsafe (NOTICE => $nickname, $si1);

                    # We do this because of central installed and locally installed modules.
                    my @avail = $self->available_modules();
                    my $x = _->unique(\@avail,0);

                    try { # Plugins can be unpredictable.
                        for my $plugin (@$x) {

                            my $is_loaded = exists $self->loaded_plugins->{$plugin} ? "active" : "inactive";
                            my $command_summary = "[plugin] $plugin $is_loaded";
                            my $conf = $self->{config_hash};
                            if(exists $conf->{plugins}{$plugin}{autoload}) {
                                my $autoload = $conf->{plugins}{$plugin}{autoload} eq 1 ? "on" : "off";
                                $command_summary .= " (autoload $autoload)";
                            }

                            $self->send_server_unsafe (PRIVMSG => $nickname, $command_summary);
                        }
                    }
                    catch($e) {
                    }
                } else {
                    my $plugin_name = '';
                    my $plugin_status = '';

                    if ( defined($plugin_name = List::MoreUtils::first_value { $name eq $_ } $self->available_modules) ) { 
                        $plugin_status = exists $self->loaded_plugins->{$name} ? "active" : "inactive";
                    } else {
                        $plugin_status = "not found";
                    }

                    my $status_msg = "[plugin] $name $plugin_status";

                    my $conf = $self->{config_hash};
                    if(exists $conf->{plugins}{$name}{autoload}) {
                        my $autoload = $conf->{plugins}{$name}{autoload} eq 1 ? "on" : "off";
                        $status_msg .= " (autoload $autoload)";
                    }
                    $self->send_server_unsafe (PRIVMSG => $nickname, $status_msg);
                }

            } elsif($arg eq 'reload') {
                if($name eq '*' || $name eq 'all') {
                    # We do this because of central installed and locally installed modules.
                    my @avail = $self->available_modules();
                    my $x = _->unique(\@avail,0);

                    for my $p (@avail) {

                        #return if exists $self->loaded_plugins->{$plugin_name};
                        my $unloaded_ok = $self->unload_plugin($p);
                        # return unless ($unloaded_ok);
                        my $added_ok = $self->load_plugin($p);

                        return unless ($added_ok);
                        # next unless ($unload_ok);

                        my $out_msg = "[plugin] $p reloaded - > by $nickname";
                        my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );
                        $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                    }
                } else {
                    my $plugin_name = '';
                    if ( defined($plugin_name = List::MoreUtils::first_value { $name eq $_ } $self->available_modules) ) {

                        #return if exists $self->loaded_plugins->{$plugin_name};
                        my $unloaded_ok = $self->unload_plugin($plugin_name);
                        # return unless ($unloaded_ok);
                        my $added_ok = $self->load_plugin($plugin_name);

                        return unless ($added_ok);

                        my $out_msg = "[plugin] $name reloaded - > by $nickname";
                        my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );
                        $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                    }
                }
            } elsif($arg eq 'autoload on') {

                if($name eq '*' || $name eq 'all') {
                    # We do this because of central installed and locally installed modules.
                    my @avail = $self->available_modules();
                    my $x = _->unique(\@avail,0);

                    my $conf = $self->{config_hash};
                    for my $p (@avail) {
                        $conf->{plugins}{$p}{autoload} = 1;
                        my $out_msg = "[plugin] $p set autoload on - > by $nickname";
                        my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );
                        $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                    }
                    $self->save_config();

                } else {
                    my $plugin_name = '';
                    if ( defined($plugin_name = List::MoreUtils::first_value { $name eq $_ } $self->available_modules) ) {
                        my $conf = $self->{config_hash};
                        $conf->{plugins}{$plugin_name}{autoload} = 1;
                        $self->save_config();

                        my $out_msg = "[plugin] $plugin_name set autoload on - > by $nickname";
                        my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );
                        $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                    }
                }
            } elsif($arg eq 'autoload off') {

                if($name eq '*' || $name eq 'all') {
                    # We do this because of central installed and locally installed modules.
                    my @avail = $self->available_modules();
                    my $x = _->unique(\@avail,0);

                    my $conf = $self->{config_hash};
                    for my $p (@avail) {
                        $conf->{plugins}{$p}{autoload} = 0;
                        my $out_msg = "[plugin] $p set autoload off - > by $nickname";
                        my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );
                        $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                    }
                    $self->save_config();

                } else {
                    my $plugin_name = '';
                    if ( defined($plugin_name = List::MoreUtils::first_value { $name eq $_ } $self->available_modules) ) {
                        my $conf = $self->{config_hash};
                        $conf->{plugins}{$plugin_name}{autoload} = 0;
                        $self->save_config();

                        my $out_msg = "[plugin] $plugin_name set autoload off - > by $nickname";
                        my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $out_msg );
                        $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
                    }
                }
            }

            return 1;
        },
        acl => $admin_access,
    );
    $self->add_func(name => 'help',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
            #my $cmd_names = _->pluck(\@commands, 'name');

            my ($cmd, $arg) = split(/ /, $message, 2);

            unless(defined $arg || length $arg) {
                my $h = "general help\n";
                $h .= "type .commands for available commands.\n";
                $h .= "use .help <command> for help on a specific command.";

                for my $line (split /\n/, $h) { 
                    $self->send_server_unsafe (PRIVMSG => $nickname, $line);
                    #$self->{con}->send_long_message ("utf8", 0, "PRIVMSG\001ACTION", $nickname, $line);
                }

                return 1;
            }

            if(lc $arg eq 'plugin' && $self->is_admin($who)) {
                my $h = "plugin <name> <command>\n";
                $h .= "name - name of plugin. optionally specify \'*\' or \'all\' for every available plugin.\n";
                $h .= "command - available commands are \'load\',\'unload\',\'reload\', and \'status\'.";

                for my $line (split /\n/, $h) { 
                    $self->send_server_unsafe (PRIVMSG => $nickname, $line);
                }

                return 1;
            }

            if(lc $arg eq 'admin' && $self->is_admin($who)) {
                my $h = "admin <command> <args>\n";
                $h .= "command - available commands are \'grep\',\'key\',\'add\',\'remove\',\'list\' or \'ls\'.\n";
                $h .= "args - optional arguments for command.";

                for my $line (split /\n/, $h) { 
                    #$self->{con}->send_long_message ("utf8", 0, "PRIVMSG\001ACTION", $nickname, $line);
                    $self->send_server_unsafe (PRIVMSG => $nickname, $line);
                }

                return 1;
            }

            if(lc $arg eq 'admin key' && $self->is_admin($who)) {
                my $h = "admin key <key>\n";
                $h .= "key - set a blowfish key for communication.";

                for my $line (split /\n/, $h) { 
                    #$self->{con}->send_long_message ("utf8", 0, "PRIVMSG\001ACTION", $nickname, $line);
                    $self->send_server_unsafe (PRIVMSG => $nickname, $line);
                }

                return 1;
            }
            if(lc $arg eq 'whitelist' && $self->is_admin($who)) {
                my $h = "whitelist <command> <args>\n";
                $h .= "command - available commands are \'add\',\'remove\',\'list\' or \'ls\'.\n";
                $h .= "args - optional arguments for command.";

                for my $line (split /\n/, $h) { 
                    #$self->{con}->send_long_message ("utf8", 0, "PRIVMSG\001ACTION", $nickname, $line);
                    $self->send_server_unsafe (PRIVMSG => $nickname, $line);
                }

                return 1;
            }
            if(lc $arg eq 'blacklist' && $self->is_admin($who)) {
                my $h = "blacklist <command> <args>\n";
                $h .= "command - available commands are \'add\',\'remove\',\'list\' or \'ls\'.\n";
                $h .= "args - optional arguments for command.";

                for my $line (split /\n/, $h) { 
                    #$self->{con}->send_long_message ("utf8", 0, "PRIVMSG\001ACTION", $nickname, $line);
                    $self->send_server_unsafe (PRIVMSG => $nickname, $line);
                }

                return 1;
            }
            if(lc $arg eq 'channel' && $self->is_admin($who)) {
                my $h = "channel <command> <args>\n";
                $h .= "command - available commands are \'mode\',\'add\',\'remove\',\'list\' or \'ls\'.\n";
                $h .= "args - optional arguments for command.";

                for my $line (split /\n/, $h) { 
                    #$self->{con}->send_long_message ("utf8", 0, "PRIVMSG\001ACTION", $nickname, $line);
                    $self->send_server_unsafe (PRIVMSG => $nickname, $line);
                }

                return 1;
            }

            if(lc $arg eq 'channel mode' && $self->is_admin($who)) {
                my $h = "channel mode <#channel> <mode> <value>\n";
                #$h .= "mode - available channel modes are \'A\'(aggressive),\'O\'(automatically op admins),\'P\'(protect admins),\'U\'(automatically shorten urls).\n";
                #$h .= "value - \'+\',\'-\',\'1\',\'0\'.";

                $h .= "mode - available channel modes are:\n";

                foreach my $mi (@channelmodes) {
                    my $cmnt = $mi->{'comment'};
                    my $m = $mi->{'mode'};
                    $h .= " \'$m\' $cmnt\n";
                }

                $h .= "value - \'+\',\'-\',\'1\',\'0\'.";

# MODES:
# +O  - auto op_admins
# +W  - auto op whitelist
# +P  - protect admins
# +V  - protect whitelist
# +U  - automatically shorten urls
# +A  - aggressive mode (kick/ban instead of -o, etc)
# +Z  - allow plugins to be used in this channel
# +F  - fast op (no cookies)
                for my $line (split /\n/, $h) { 
                    #$self->{con}->send_long_message ("utf8", 0, "PRIVMSG\001ACTION", $nickname, $line);
                    $self->send_server_unsafe (PRIVMSG => $nickname, $line);
                }

                return 1;
            }

            if(lc $arg eq 'trivia' && $self->is_admin($who)) {
                my $h = "trivia <command>\n";
                $h .= "command - available commands are \'start\',\'stop\'.\n";

                for my $line (split /\n/, $h) { 
                    #$self->{con}->send_long_message ("utf8", 0, "PRIVMSG\001ACTION", $nickname, $line);
                    $self->send_server_unsafe (PRIVMSG => $nickname, $line);
                }

                return 1;
            }
            return 1;
        },
        acl => $all_access_except_blacklist,
    );

    $self->add_func(name => 'statistics',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
            my $running_elapsed = Time::Elapsed::elapsed( time - $self->start_time );
            my $basic_info = sprintf("Hadouken %s by dek. Current uptime: %s", #$VERSION, $running_elapsed);
                String::IRC->new($VERSION)->bold, 
                String::IRC->new($running_elapsed)->bold );
            my $msg = sprintf '+OK %s', $self->_chat_encrypt( $who, $basic_info); #, $self->{keys}->[0] );
            $self->send_server_unsafe (PRIVMSG => $nickname, $msg);

            return 1;
        },
        acl => $admin_access,
    );

#    $self->add_func(name => 'btc', 
#        delegate => sub {
#            my ($who, $message, $channel, $channel_list) = @_;
#            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
#            my $json = $self->fetch_json('https://btc-e.com/api/3/ticker/btc_usd');
#            my $json2 = $self->fetch_json('https://crypto-trade.com/api/1/ticker/btc_usd');
#            my $ret =  "[btc_usd\@btce] Last: $json->{btc_usd}->{last} Low: $json->{btc_usd}->{low} High: $json->{btc_usd}->{high} Avg: $json->{btc_usd}->{avg} Vol: $json->{btc_usd}->{vol}";
#            my $ret2 = "[btc_usd\@ct]   Last: $json2->{data}->{last} Low: $json2->{data}->{low} High: $json2->{data}->{high} Vol(usd): $json2->{data}->{vol_usd}";
#            $self->send_server_unsafe (PRIVMSG => $channel, $ret);
#            $self->send_server_unsafe (PRIVMSG => $channel, $ret2);
    #
#            return 1;
#        },
#        acl => $admin_access,
#    );
    #
#    $self->add_func(name => 'ltc', 
#        delegate => sub {
#            my ($who, $message, $channel, $channel_list) = @_;
#            my $json = $self->fetch_json('https://btc-e.com/api/3/ticker/ltc_usd');
#            my $json2 = $self->fetch_json('https://crypto-trade.com/api/1/ticker/ltc_usd');
#            my $ret =  "[ltc_usd\@btce] Last: $json->{ltc_usd}->{last} Low: $json->{ltc_usd}->{low} High: $json->{ltc_usd}->{high} Avg: $json->{ltc_usd}->{avg} Vol: $json->{ltc_usd}->{vol}";
#            my $ret2 = "[ltc_usd\@ct]   Last: $json2->{data}->{last} Low: $json2->{data}->{low} High: $json2->{data}->{high} Vol(usd): $json2->{data}->{vol_usd}";
    #
#            $self->send_server_unsafe (PRIVMSG => $channel, $ret);
#            $self->send_server_unsafe (PRIVMSG => $channel, $ret2);
    #
#            return 1;
#        },
#        acl => $admin_access,
#    );
    #
#    $self->add_func(name => 'eur2usd', 
#        delegate => sub {
#            my ($who, $message, $channel, $channel_list) = @_;
#            my $json = $self->fetch_json('https://btc-e.com/api/3/ticker/eur_usd');
#            my $ret = "[eur_usd] Last: $json->{eur_usd}->{last} Low: $json->{eur_usd}->{low} High: $json->{eur_usd}->{high} Avg: $json->{eur_usd}->{avg} Vol: $json->{eur_usd}->{vol}";
#            $self->send_server_unsafe (PRIVMSG => $channel, $ret);
    #
#            return 1;
#        },
#        acl => $all_access_except_blacklist,
#    );

    $self->{con}->reg_cb (
        connect => sub {
            my ($con, $err) = @_;
            if (defined $err) {
                warn "* Couldn't connect to server: $err\n";
                if ($self->{reconnect}){
                    warn "* Reconnecting in ".$self->{reconnect_delay}."\n";
                    Time::HiRes::sleep $self->{reconnect_delay};
                    warn "* Trying to reconnecting...\n";
                    $self->{reconnecting} = 1;
                    $self->_start;
                } else {
                    $self->{c}->broadcast;
                }
            }
        },
        registered => sub {
            $self->{connected} = 1;
            $self->_set_connect_time(time());
        },
        disconnect => sub {
            $self->{connected} = 0;
            warn "* Disconnected\n";
            if ($self->{reconnect}) {
                warn "* Reconnecting in ".$self->{reconnect_delay}."\n";
                Time::HiRes::sleep $self->{reconnect_delay};
                warn "* Trying to reconnect\n";
                $self->_start;

            } else {
                $self->{c}->broadcast;
            }
        },
        join => sub {
            my ($con,$nick, $channel, $is_myself) = (@_);
            return if $is_myself;
            my $ident = $con->nick_ident($nick);
            return unless defined $ident;

            my $cur_channel_clean = $channel;
            $cur_channel_clean =~ s/^\#//;

            my $server_hash_ref = $self->{current_server};

            # Auto OP bots.
            if($self->is_bot($ident)) {
                
                $self->op_user($channel,$nick,$ident);

                #my $cookie = $self->makecookie($ident,$self->{nick},$channel);
                #my $test = $self->checkcookie($ident,$self->{nick},$channel,$cookie);
                #$self->send_server_unsafe( MODE => $channel, '+o-b', $nick, $cookie);
            }

            my $opped_user = 0;

            if($self->is_admin($ident)) {
                if($self->channel_mode_isset($cur_channel_clean, Hadouken::CMODE_OP_ADMIN)) { # Automatically OP admins.
                    
                    $self->op_user($channel,$nick,$ident);
                    #my $cookie = $self->makecookie($ident,$self->{nick},$channel);
                    #my $test = $self->checkcookie($ident,$self->{nick},$channel,$cookie);
                    #my $ref_modes = $self->{con}->nick_modes ($channel, $nick);

                    # Make sure not already opped.
                    #if(defined $ref_modes && $ref_modes->{'o'}) {
                    #    warn "* Already opped, skipping";
                    #} else {
                    #$self->send_server_unsafe( MODE => $channel, '+o-b', $nick, $cookie);
                    $opped_user = 1;
                    #}
                }
            }

            if($self->whitelisted($ident)) {
                if($self->channel_mode_isset($cur_channel_clean, Hadouken::CMODE_OP_WHITELIST)) { # Automatically OP whitelists.
                    # We already opped the user, since somehow he is added as admin and whitelisted. Should not do that, but I won't restrict anything.
                    unless($opped_user) {
                        
                        $self->op_user($channel,$nick,$ident);
                        #my $cookie = $self->makecookie($ident,$self->{nick},$channel);
                        #my $test = $self->checkcookie($ident,$self->{nick},$channel,$cookie);
                        # my $ref_modes = $self->{con}->nick_modes ($channel, $nick);

                        # Make sure not already opped.
                        #if(defined $ref_modes && $ref_modes->{'o'}) {
                        #    warn "* Already opped, skipping";
                        #} else {
                        #$self->send_server_unsafe( MODE => $channel, '+o-b', $nick, $cookie);
                        #}
                    }
                }
            }

        },
        kick => sub {
            my($con, $kicked_nick, $channel, $is_myself, $msg, $kicker_nick) = (@_);

            my $ident = $con->nick_ident($kicker_nick);

            my $cur_channel_clean = $channel;
            $cur_channel_clean =~ s/^\#//;

            $is_myself = 0 if $is_myself eq '';

            warn "* KICK CALLED -> $kicked_nick by $kicker_nick from $channel with message $msg -> is myself: $is_myself!\n";
            # warn "my nick is ". $self->{con}->nick() ."\n";
            if($self->{con}->nick() eq $kicked_nick || $self->{con}->is_my_nick($kicked_nick)) {
                if($self->{rejoin_on_kick}) {
                    warn "* Rejoining $channel automatically\n";
                    $self->send_server_unsafe (JOIN => $channel);
                }
                # my $si = String::IRC->new($kicker_nick)->red->bold;
                # $self->send_server_unsafe (PRIVMSG => $channel,"kicked by $si, behavior logged");
            } else {

                if($self->is_bot($con->nick_ident($kicked_nick))) {
                    warn "* KICKED BOT";
                    if($self->channel_mode_isset($cur_channel_clean, Hadouken::CMODE_AGGRESSIVE)) {

                        if(!($self->{con}->is_my_nick($ident)) 
                            && !($self->is_admin($ident)) 
                            && !($self->is_bot($ident)) 
                            && !($self->whitelisted($ident))) {

                            my (undef,$host) = split /@/, $ident;
                            my $banmask = "*!*@".$host;

                            if($self->matches_mask($banmask, $ident)) {

                                warn "* Banning $ident from $cur_channel_clean (AGGRESSIVE MODE)";

                                $self->send_server_unsafe( MODE => $channel, '+b', $banmask);
                            } else {

                                warn "* Ban mask didn't match when trying to ban!";
                            }
                        }


                        warn "* Aggressive mode is disabling whitelist protection and auto-ops so they cannot regain ops.";
                        $self->channel_mode_human($cur_channel_clean,'-V-W');

                        $self->send_server_unsafe( KICK => $channel, $kicker_nick, "$kicker_nick.") 
                        unless $self->{con}->is_my_nick($kicker_nick) || $self->is_admin($ident) || $self->is_bot($ident);

                    } else {

                        $self->send_server_unsafe( MODE => $channel, '-o', $kicker_nick) 
                        unless $self->{con}->is_my_nick($kicker_nick) || $self->is_admin($ident) || $self->is_bot($ident);

                    }

                }







            }
        },
        dcc_request => sub {
            my ($con, $id, $src, $type, $arg, $addr, $port) = @_;

            warn "* DCC Request from $addr\n";

            #$self->{con}->dcc_accept($id);

            #warn "* DCC Accepting\n";
        },
        dcc_chat_msg => sub {
            my ($con, $id, $msg) = @_;

            warn "* DCC CHAT MSG $msg\n";

            if ($msg =~ s/^\+OK //) {
                #$msg = $self->_decrypt( $msg, $self->{keys}{all}->[0] );
                #$msg =~ s/\0//g;

                #warn "* Decrypted $msg\n";

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

            if($self->is_admin($who)) {
                try {
                    if ($message =~ s/^\+OK //) {
                        $message = $self->_chat_decrypt( $who, $message); #, $self->{keys}->[0] );
                        $message =~ s/\0//g;

                        warn "* Decrypted $message\n";

                        ## We change the channel to who because that's who we are privmsg'ing results to.
                        $channel = $who;

                        #my $init_msg = 'Hello there how are you';
                        #my $msg = sprintf '+OK %s', $self->_encrypt( $init_msg, $self->{keys}->[0] );
                        #$self->send_server_unsafe(PRIVMSG => $nickname, $msg);
                    }
                } catch($e) {
                    $message = $ircmsg->{params}[1];
                    warn "Error decrypting $e\n";
                }
            }


            my $cmd = undef;
            if ( defined($cmd = List::MoreUtils::first_value { $message =~ /$command_prefix$_->{'regex'}/ } @commands) ) {

                if($cmd->{'channel_only'}) {
                    return unless ((defined $channel) && ($self->{con}->is_channel_name($channel)));
                }

                #unless($self->is_admin($who) && $cmd->{'require_admin'}) {
                #    warn "* test";
                #    return unless ((defined $channel) && ($self->{con}->is_channel_name($channel)));
                #}

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
            } 
            else {

                my $cur_channel_clean = $channel;
                $cur_channel_clean =~ s/^\#//;
                # Shorten urls for this channel if the mode is set.
                my $uri = undef;
                #
                if($self->channel_mode_isset($cur_channel_clean, Hadouken::CMODE_SHORTEN_URLS)) {

                if (( ($uri) = $message =~ /$RE{URI}{HTTP}{-scheme=>'https?'}{-keep}/ ) ) { #m{($RE{URI})}gos ) {
                    warn "* Matched a URL $uri\n";
                    #if($self->channel_mode_isset($cur_channel_clean, Hadouken::CMODE_SHORTEN_URLS)) {
                        # warn "* shorten_urls IS set for this channel";
                        # Only get titles if admin, since we trust admins.
                        my $get_title = $self->is_admin($who);
                        my ($shrt_url,$shrt_title) = $self->_shorten($uri, $get_title );
                        if(defined($shrt_url) && $shrt_url ne '') {
                            if(defined($shrt_title) && $shrt_title ne '') {
                                $self->send_server_unsafe (PRIVMSG => $channel, "$shrt_url ($shrt_title)");
                                } else {
                                $self->send_server_unsafe (PRIVMSG => $channel, "$shrt_url");      
                                }
                            }
                            #}
                     }
                }

                # Try to match a plugin command last(but not least).

                my $clean_msg = AnyEvent::IRC::Util::filter_colors($message);
                # Make sure plugins are allowed in this channel.
                if(!($self->{con}->is_channel_name($channel)) || $self->channel_mode_isset($channel, Hadouken::CMODE_PLUGINS_ALLOWED)) {

                    my $user_admin = $self->is_admin($who);
                    my $user_whitelisted = $self->whitelisted($who);

                    my $plugin_channel = $self->{con}->is_channel_name($channel) ? $channel : $nickname;

                    # Regex is cached ahead of time
                    for my $plugin_regex (@{$self->{plugin_regexes}}) {
                        my $plugin = $plugin_regex->{name};
                        my $regex = $plugin_regex->{regex};
                        if($clean_msg =~ /$command_prefix$regex/) {

                            $clean_msg =~ s/$command_prefix//g;

                            my $m = $self->_plugin($plugin); # lazy load plugin :)
                            #my $plugin_acl_ret = $m->acl_check($nickname, $ident, $clean_msg, $channel || undef,$user_admin,$user_whitelisted);
                            my $plugin_acl_ret = $m->acl_check( $plugin_acl_func->($who, $clean_msg, $plugin_channel, $channel_list || undef) );

                            warn "* Plugin $plugin -> ACL returned $plugin_acl_ret\n";
                            if($plugin_acl_ret) {
                                warn "* Plugin $plugin -> Calling delegate\n";
                                my $cmd_ret = $m->command_run($nickname, $ident, $clean_msg, $plugin_channel, $user_admin, $user_whitelisted);
                            }
                        }
                    }
                }

                # Just a silly thing. If someone say one of these words, we counter it.
                if($channel eq '#regexgolf') {
                    if($nickname ne 'hadouken') {
                        my @tmp = @{$self->{wots}};
                        my $wotcnt = scalar @tmp;
                        if(@tmp && $wotcnt > 0) {
                            my $wot = undef;
                            if ( defined($wot = List::MoreUtils::last_value { lc($message) =~ /\s$_\s?/ } @tmp) ) {
                                my $rand_mate = $tmp[rand @tmp];
                                $self->send_server_unsafe(PRIVMSG => $channel, "i ain't your $wot, $rand_mate");
                            }
                        }
                    }
                }

                #if($channel eq '#trivia') {
                #   if($nickname eq 'utonium') {
                #       if($message =~ 'QUESTION' || $message =~ 'googled the answer' || $message =~ 'start giving answers like this one') {
                #           my $stripped = $self->_decode_irc($message);
                #           $stripped =~ s/\x03\x31.*?\x03/ /g;
                #           $stripped =~ s/[\x20\x39]/ /g;
                #           $stripped =~ s/[\x30\x2c\x31]//g;
                #           $stripped = $self->_strip_color($stripped);
                #           $stripped =~ s/\h+/ /g;                            
                #           $stripped .= "\n";
                #            $self->hexdump("Unstripped",$stripped);
                #           open(FILE,">>".$self->{ownerdir}.'/../data/new_questions_parsed');
                #print FILE $stripped;
                #           close(FILE);
                #       }
                #}
                #}

                # Try to match to trivia!
                if($self->{triviarunning} && $channel eq $self->{trivia_channel}) {
                    my $old_mask = $self->{_masked_answer};
                    my $new_mask = $self->check_and_reveal($clean_msg);

                    if(defined $old_mask && $old_mask ne '' && defined $new_mask && $new_mask ne '') {
                        if($old_mask ne $new_mask) {
                            if($message eq $self->{_answer}) {
                                my $answer_elapsed = sprintf "%.1f", time - $self->{_question_time};

                                unless(exists $self->{streak}) {
                                    $self->{streak} = ();
                                }

                                push(@{$self->{streak}},$nickname);

                                my $in_a_row = 0;
                                foreach my $z ( @{$self->{streak}} ) {
                                    unless($z eq $nickname) {
                                        $in_a_row = 0;
                                        last;
                                    } else {
                                        $in_a_row++;
                                    }
                                }


                                $self->{_masked_answer} = '';

                                $self->send_server_unsafe(PRIVMSG => $self->{trivia_channel},"Yes! $nickname GOT IT! -> ".$self->{_answer}." <- in $answer_elapsed seconds and receives --> ".$self->{_current_points}." <-- points!");

                                $self->{_scores}{$nickname}{score} += $self->{_current_points};

                                # warn $self->{_scores}{$nickname}{score};

                                if($in_a_row > 0 && $in_a_row % 10 == 0) {
                                    $self->send_server_unsafe(PRIVMSG => $self->{trivia_channel}," $nickname has won $in_a_row in a row, and received a --> 500 <-- point bonus!");
                                    $self->{_scores}{$nickname}{score} += 500;
                                }

                                my $point_msg = $self->{_current_points}. " points has been added to your score! total score for ". $nickname ." is ".$self->{_scores}{$nickname}{score};
                                $self->send_server_unsafe(PRIVMSG => $self->{trivia_channel}, $point_msg);
                                $self->{_clue_number} = 0;

                                my $z = $self->_calc_trivia_rankings();
                                my $user_rank = $self->_trivia_ranking($nickname);
                                #warn "user rank is $user_rank";
                                #print Dumper($self->{_rankings});
                                my @rankings = @{$self->{_rankings}};
                                #rint Dumper(@rankings);
                                my $pos_prev = $rankings[$user_rank - 2] || undef;
                                my $pos_next = $rankings[$user_rank + 2] || undef;

                                if($user_rank == 1 && defined $pos_next) {
                                    my $points_ahead = $self->{_scores}{$nickname}{score} - $self->{_scores}{$pos_next}{score};
                                    my $first_place_msg = "  $nickname is $points_ahead points ahead for keeping 1st place!";
                                    $self->send_server_unsafe(PRIVMSG => $self->{trivia_channel},$first_place_msg);
                                } else {
                                    if(defined $pos_prev) {
                                        my $points_needed = $self->{_scores}{$pos_prev}{score} - $self->{_scores}{$nickname}{score};
                                        my $position_message = "  $nickname needs $points_needed points to take over position ". $self->{_scores}{$pos_prev}{rank};
                                        $self->send_server_unsafe(PRIVMSG => $self->{trivia_channel},$position_message);
                                    }
                                }

                                my $msg_t = "Next question in less than 15 seconds... Get Ready!";
                                $self->send_server_unsafe(PRIVMSG => $self->{trivia_channel}, $msg_t);
                            } else {
                                $self->send_server_unsafe(PRIVMSG => $self->{trivia_channel},"  Answer: $new_mask"); 
                            }
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

                if($cmd eq 'NOTICE') {
                    warn "* NOTICE ". $params ."\n";

                    my ($notice_dest,$notice_msg) = @{$msg->{params}};

                    if($notice_dest eq $self->{nick}) {
                        if($notice_msg  =~ 'DH1080_') {

                            my ($command, $cbcflag, $peer_public) = $notice_msg =~ /DH1080_(INIT|FINISH)(_cbc)? (.*)/i;

                            $self->keyx_handler($notice_msg, $nick);

                            warn "* Key Exchange Initialized\n";

                        }
                    }
                }

                if($cmd eq 'MODE') {
                    my ($chan, $modeset) = @{$msg->{params}};
                    if(defined $chan && $chan ne '' && $chan =~ /^#/ ) {
                        my $cur_channel_clean = $chan;
                        $cur_channel_clean =~ s/^\#//;

                        my $server_hash_ref = $self->{current_server};

                        #if($self->channel_mode_isset($cur_channel_clean, Hadouken::CMODE_PROTECT_ADMIN) #{{{#}}}
                        #    || $self->channel_mode_isset($cur_channel_clean, Hadouken::CMODE_PROTECT_WHITELIST)) {

                        # if(exists $server_hash_ref->{channel}{$cur_channel_clean} && $server_hash_ref->{channel}{$cur_channel_clean}{protect_admins} == 1) {

                        my @x = List::MoreUtils::after { $_ =~ '-o' } @{$msg->{params}};

                        if(@x) {

                            my @admins = grep { $self->is_admin($con->nick_ident($_)) } @x;
                            my @wls = grep { $self->whitelisted($con->nick_ident($_)) } @x;
                            my @bots = grep { $self->is_bot($con->nick_ident($_)) } @x;


                            # Aggressive bot protection:
                            # A user whose ACL level is lower than ADMIN will be kicked.
                            # A user who is whose ACL is lower than WHITELIST will be kicked and banned.

                            # Non-Aggressive bot protetion:
                            # A user whose ACL level is lower than ADMIN will be de-opped.

                            # BOTS ARE ALWAYS PROTECTED.

                            if(@bots) {

                                if($self->channel_mode_isset($cur_channel_clean, Hadouken::CMODE_AGGRESSIVE)) {

                                    if(!($self->{con}->is_my_nick($nick)) && !($self->is_admin($ident)) && !($self->is_bot($ident)) && !($self->whitelisted($ident))) {

                                        my (undef,$host) = split /@/, $ident;
                                        my $banmask = "*!*@".$host;

                                        if($self->matches_mask($banmask, $ident)) {

                                            warn "* Banning $ident from $chan (AGGRESSIVE MODE)";

                                            $self->send_server_unsafe( MODE => $chan, '+b', $banmask);
                                        } else {

                                            warn "* Ban mask didn't match when trying to ban!";
                                        }
                                    }


                                    warn "* Aggressive mode is disabling whitelist protection and auto-ops so they cannot regain ops.";
                                    $self->channel_mode_human($cur_channel_clean,'-V-W');

                                    $self->send_server_unsafe( KICK => $chan, $nick, "$nick.") 
                                    unless $self->{con}->is_my_nick($nick) || $self->is_admin($ident) || $self->is_bot($ident);

                                } else {

                                    $self->send_server_unsafe( MODE => $chan, '-o', $nick) 
                                    unless $self->{con}->is_my_nick($nick) || $self->is_admin($ident) || $self->is_bot($ident);

                                }

                                my $it = List::MoreUtils::natatime 4, @bots;

                                while (my @vals = $it->()) {
                                    my $mode = '+';

                                    $mode .= 'o' x ($#vals + 1);
                                    $mode .= '-b';

                                    my $cookie = $self->makecookie($nick,$self->{nick},$chan);
                                    my $test = $self->checkcookie($nick,$self->{nick},$chan,$cookie);
                                    push(@vals,$cookie);
                                    #unshift(@vals,$cookie);
                                    warn "* Protect triggered in $chan, setting MODE $mode ".join('  ',@vals) ."\n";
                                    unshift(@vals,$mode);

                                    $self->send_server_unsafe( MODE => $chan, @vals);
                                }

                            }


                            # Aggressive admin protection:
                            # A user whose ACL level is lower than ADMIN will be kicked (BOT is equal to admin).
                            # A user who is whose ACL is lower than WHITELIST will be kicked and banned.

                            # Non-Aggressive admin protetion:
                            # A user whose ACL level is loser than ADMIN will be de-opped.

                            # If one of the admins that was deopped is the owner, the user will be kicked.


                            if(@admins) {

                                my $owner = _->detect(\@admins, sub { 
                                        my $k = $con->nick_ident($_);
                                        warn "NICK_IDENT $k";
                                        if($self->matches_mask($self->{admin},$k)) {
                                            return $_;
                                        } else {
                                        }
                                    });


                                if($self->channel_mode_isset($cur_channel_clean, Hadouken::CMODE_PROTECT_ADMIN)) {

                                    if($self->channel_mode_isset($cur_channel_clean, Hadouken::CMODE_AGGRESSIVE)) {

                                        $self->send_server_unsafe( KICK => $chan, $nick, "$nick.") 
                                        unless $self->{con}->is_my_nick($nick) || $self->is_admin($ident) || $self->is_bot($ident);

                                    } else {

                                        $self->send_server_unsafe( MODE => $chan, '-o', $nick) 
                                        unless $self->{con}->is_my_nick($nick) || $self->is_admin($ident) || $self->is_bot($ident);

                                    }

                                    # Always kick if they -o owner, unless the owner does it himself.
                                    $self->send_server_unsafe(KICK => $chan, $nick, "$nick.") if defined $owner && length $owner && $nick ne $owner;

                                    #if($self->channel_mode_isset($cur_channel_clean, Hadouken::CMODE_PROTECT_ADMIN)) {

                                    my $it = List::MoreUtils::natatime 4, @admins;

                                    while (my @vals = $it->()) {
                                        my $mode = '+';

                                        $mode .= 'o' x ($#vals + 1);
                                        $mode .= '-b';

                                        my $cookie = $self->makecookie($nick,$self->{nick},$chan);
                                        my $test = $self->checkcookie($nick,$self->{nick},$chan,$cookie);
                                        push(@vals,$cookie);
                                        #unshift(@vals,$cookie);
                                        warn "* Protect triggered in $chan, setting MODE $mode ".join('  ',@vals) ."\n";
                                        unshift(@vals,$mode);

                                        $self->send_server_unsafe( MODE => $chan, @vals);
                                    }
                                }
                            } # // if(@admins) {

                            if($self->channel_mode_isset($cur_channel_clean, Hadouken::CMODE_PROTECT_WHITELIST)) {

                                if(@wls) {

                                    # If a whitelist user is deopped by a BOT or ADMIN, we do not protect.
                                    # And if we are in aggressive mode, we disable auto-op and protection for whitelist users in this channel.

                                    if($self->{con}->is_my_nick($nick) || $self->is_admin($ident) || $self->is_bot($ident)) {

                                        warn "* Not protecting whitelist, BOT or ADMIN deopped them.";

                                        if($self->channel_mode_isset($cur_channel_clean, Hadouken::CMODE_AGGRESSIVE)) {

                                            warn "* Aggressive mode is disabling whitelist protection and auto-ops so they cannot regain ops.";

                                            $self->channel_mode_human($cur_channel_clean,'-V-W');

                                        }

                                    } else {

                                        my $it2 = List::MoreUtils::natatime 4, @wls;

                                        while (my @vals2 = $it2->()) {
                                            my $mode = '+';
                                            $mode .= 'o' x ($#vals2 + 1);
                                            $mode .= '-b';
                                            my $cookie = $self->makecookie($nick,$self->{nick},$chan);
                                            my $test = $self->checkcookie($nick,$self->{nick},$chan,$cookie);
                                            push(@vals2,$cookie);
                                            warn "* Protect triggered in for whitelist $chan, setting MODE $mode ".join('  ',@vals2) ."\n";
                                            unshift(@vals2,$mode);

                                            $self->send_server_unsafe( MODE => $chan, @vals2);
                                        }
                                    }
                                } # // if(@wls) {

                            }
                        }

                        my @bans = List::MoreUtils::after { $_ =~ /\+b/ } @{$msg->{params}};
                        if(@bans) {

                            unless($self->{con}->is_my_nick($nick) || $self->is_admin($ident) || $self->is_bot($ident)) {

                                warn "* Protect triggered in $chan, UNBANNING ".join('  ',@bans) ."\n";

                                # Only de-op unless we are in Aggressive mode.
                                # If so, then we kick and ban.

                                $self->send_server_unsafe( MODE => $chan, '-o', $nick) 
                                unless $self->{con}->is_my_nick($nick) || $self->is_admin($ident) || $self->is_bot($ident);

                                if($self->channel_mode_isset($cur_channel_clean, Hadouken::CMODE_AGGRESSIVE)) {

                                    if(!($self->{con}->is_my_nick($nick)) && !($self->is_admin($ident)) && !($self->is_bot($ident)) && !($self->whitelisted($ident))) {

                                        my (undef,$host) = split /@/, $ident;
                                        my $banmask = "*!*@".$host;

                                        if($self->matches_mask($banmask, $ident)) {

                                            warn "* Banning $ident from $chan (AGGRESSIVE MODE)";

                                            $self->send_server_unsafe( MODE => $chan, '+b', $banmask);
                                        } else {

                                            warn "* Ban mask didn't match when trying to ban!";
                                        }


                                        $self->send_server_unsafe( KICK => $chan, $nick, "$nick.");
                                    }

                                }

                                foreach my $ban (@bans) {
                                    warn "UNBANNING $ban";
                                    $self->send_server_unsafe( MODE => $chan, '-b', $ban);
                                    # $self->send_server_unsafe( MODE => $chan, '-o-b', $nick, $ban);
                                }

                            } else {

                                warn "* Admin is banning users in $chan, ".join('  ',@bans) ."\n";

                                foreach my $ban (@bans) {

                                    my $n_ban = $self->normalize_mask($ban);

                                    # Admin can ban anyone except:
                                    # Admin can't ban other admins
                                    # OR BOTS!
                                    if( (grep { $self->matches_mask($n_ban, $self->normalize_mask($_->[0].'@'.$_->[1]) ) } @{$self->{adminsdb}})
                                        || (grep { $self->matches_mask($n_ban, $self->normalize_mask($_->[0].'@'.$_->[1]) ) } @{$self->{botsdb}}) ) {

                                        $self->send_server_unsafe( MODE => $chan, '-b', $ban);

                                        unless($self->{con}->is_my_nick($nick) || $self->is_admin($ident) || $self->is_bot($ident)) {
                                            $self->send_server_unsafe( MODE => $chan, '-o-b', $nick, $ban);
                                        } else {
                                            $self->send_server_unsafe( MODE => $chan, '-b', $ban);
                                        }
                                    }

                                    # Can't ban whitelisted!
                                    if(grep { $self->matches_mask($n_ban, $self->normalize_mask($_->[0].'@'.$_->[1]) ) } @{$self->{whitelistdb}} ) {

                                        #$self->send_server_unsafe( MODE => $chan, '-b', $ban);

                                        unless ($self->{con}->is_my_nick($nick) || $self->is_admin($ident) || $self->is_bot($ident)) {
                                            $self->send_server_unsafe( MODE => $chan, '-o-b', $nick, $ban);
                                        } else {
                                            $self->send_server_unsafe( MODE => $chan, '-b', $ban);
                                        }
                                    }
                                }
                            }
                        }



                        #}
                    }

                }
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

# TODO: Move all trivia functions into plugins.
sub _start_trivia {
    my ($self,$channel) = @_;

    if($self->{triviarunning}) {
        return 1;
    }

    $self->{triviarunning} = 1;
    $self->{trivia_channel} = $channel;

    #$self->_trivia_func;

    if(-e $self->{ownerdir}.'/../data/scores.json') {
        open(my $fh, $self->{ownerdir}.'/../data/scores.json') or die $!;
        my $json_data;
        read($fh,$json_data, -s $fh); # Suck in the whole file
        close $fh;

        my $temp_scores = JSON->new->allow_nonref->decode($json_data);
        #$self->{_scores} = %{$temp_scores};

        %{$self->{_scores}} = %{$temp_scores};

        $self->_calc_trivia_rankings;
    }

    undef $self->{triv_timer};
    $self->{triv_timer} = AnyEvent->timer (after => 0, interval => 15, cb => sub { $self->_trivia_func; } );

    return 1;
}

sub _stop_trivia {
    my ($self) = @_;

    unless($self->{triviarunning}) {
        return 1;
    }

    $self->_save_trivia_scores;

    $self->{_clue_number} = 0;
    $self->{triviarunning} = 0;
    $self->{trivia_channel} = '';

    $self->{triv_timer} = undef;

    delete $self->{triv_timer};

    return 1;
}

sub _save_trivia_scores {
    my ($self) = @_;

    return unless defined $self->{_scores};

    $self->_calc_trivia_rankings;

    open(my $fh,">".$self->{ownerdir}.'/../data/scores.json');
    my %scorez = %{$self->{_scores}};
    my $json_data = JSON->new->allow_nonref->encode(\%scorez);
    print $fh $json_data;
    close($fh);

    return 1;
}

sub _calc_trivia_rankings {
    my ($self) = @_;
    
    my @rankings = sort { $self->{_scores}->{$b}->{score} <=> $self->{_scores}->{$a}->{score} } keys %{$self->{_scores}};
    my $i = 0;
    for my $p (@rankings) {
        $self->{_scores}->{$p}->{rank} = ++$i;
    }

    @{$self->{_rankings}} = @rankings;

    return 1;
}

sub _trivia_ranking {
    my $self = shift;
    my $username = shift;

    return 0 unless defined $username;

    if (exists $self->{_scores}{$username}) {
        #$self->_calc_trivia_rankings unless exists $self->{_scores}{$username}{rank};
        my $rank = $self->{_scores}{$username}{rank};
        return $rank;
    } else {
        return 0;
    }
}

sub _get_new_question {
    my $self = shift;

    my $questionsdir = $self->{ownerdir}.'/../data/questions';

    return 0 unless(-d $questionsdir);

    opendir(DIR, $questionsdir) or die $!;

    my @question_files 
    = grep { 
    /^questions/            # question_00
    && -f "$questionsdir/$_"    # and is a file
    } readdir(DIR);

    closedir(DIR);

    my @qf = List::Util::shuffle @question_files;
    my $blah = $questionsdir."/".$qf[0];
    my $line;
    open FILE,"<$blah" or die("Cant open $!\n");
    srand;
    rand($.) < 1 && ($line = $_) while <FILE>;
    close(FILE);


    my($question,$temp_answer) = split(/`/,$line);

    chomp($question);
    chomp($temp_answer);

    $self->{_question} = $question;
    $self->{_answer} = lc($temp_answer);
    $self->{_masked_answer} = '';

    foreach my $char (split //, $self->{_answer}) {
        if ($char =~ /[[:alnum:]]/) {
            $self->{_masked_answer} .= '.';
        } else {
            $self->{_masked_answer} .= $char;
        }
    }
}

sub give_clue {
    my $self = shift;

    my $letter = ' ';
    my $index;

    while(!($letter =~ /[[:alnum:]]/)) {
        $index = rand length $self->{_answer};
        $letter = substr($self->{_answer},$index,1);
        my $masked_letter = substr($self->{_masked_answer},$index,1);
        if($masked_letter eq $letter) {
            $letter = ' ';
        }
    }

    my $temp = $self->{_masked_answer};
    substr $temp, $index, 1, $letter;

    $self->{_masked_answer} = $temp;

    return $self->{_masked_answer};
}

sub check_and_reveal {
    my $self = shift;
    my $guess = shift;

    return '' unless exists $self->{_masked_answer} && $self->{_masked_answer} ne '';
    return '' if(length($guess) > length($self->{_answer}));

    my @chars = split(//,$guess);
    my @masked_chars = split(//,$self->{_masked_answer});
    my @real_answer = split(//,$self->{_answer});

    for my $index (0 .. $#chars) {

        next unless $chars[$index] =~ /[[:alnum:]]/;

        my $answer_letter = $masked_chars[$index];
        next if $masked_chars[$index] =~ /[[:alnum:]]/;

        my $guess_letter = $chars[$index];

        if(lc($guess_letter) eq lc($real_answer[$index])) {

            my $temp = $self->{_masked_answer};
            substr $temp, $index, 1, $chars[$index];

            $self->{_masked_answer} = $temp;
        }
    }

    return $self->{_masked_answer};
}


sub _trivia_func {
    my $self = shift;

    return unless $self->{triviarunning};

    my %points = ( 0 => 20, 1 => 17, 2 => 11, 3 => 5 );

    $self->{_clue_number} = 0 unless exists $self->{_clue_number};


    if($self->{_clue_number} == 0) {

        $self->_get_new_question;

        $self->{_current_points} = $points{$self->{_clue_number}};

        warn $self->{_answer},"\n";

        my $msg = "Question, worth ".$self->{_current_points}." points: ".$self->{_question};
        $self->send_server_unsafe(PRIVMSG => $self->{trivia_channel}, $msg );

        my $clue_msg = "  Answer: ".$self->{_masked_answer};
        $self->send_server_unsafe(PRIVMSG => $self->{trivia_channel}, $clue_msg );

        $self->{_question_time} = time();

        $self->{_clue_number}++;
    } elsif( $self->{_clue_number} < 4) {

        $self->{_current_points} = $points{$self->{_clue_number}};

        my $msg = "  Down to ".$self->{_current_points}." points: ".$self->give_clue;
        $self->send_server_unsafe(PRIVMSG => $self->{trivia_channel}, $msg );
        $self->{_clue_number}++;
    } else {

        my $msg = "No one got it. The answer was: ". $self->{_answer};
        $self->send_server_unsafe(PRIVMSG => $self->{trivia_channel}, $msg );
        my $msg_t = "Next question in less than 15 seconds... Get Ready!";
        $self->send_server_unsafe(PRIVMSG => $self->{trivia_channel}, $msg_t);

        $self->{_clue_number} = 0;
        $self->_get_new_question;
    }

}

sub _start {
    my $self = shift;

    $self->_buildup();

    my $server_count = scalar @{$self->{servers}};
    $self->{current_server_index} = int rand $server_count;

    my $server_hashref = $self->{servers}[$self->{current_server_index}]; 
    my @servernames = keys %{$server_hashref};
    my $server_name = $servernames[0];

    $self->{current_server} = $server_hashref->{$server_name};
    $self->{server_name} = $server_name;
    my @channels = keys %{$server_hashref->{$server_name}{channel}};

    my $conf = $self->{config_hash};

    foreach my $k (keys %{$conf->{keys}}) {
        my $user = $k; #$conf->{keys}{$k};
        my $key = $conf->{keys}{$k}{key};
        $self->_set_key($user,$key);
    }

    my $count = List::MoreUtils::true { /dek/ } @channels;
    push(@channels,'#dek') unless $count > 0;

    # TODO: Handle if no channels defined.
    foreach my $chan (@channels) {
        #foreach my $chan ( @{$server_hashref->{$server_name}{channel}} ) {
        $chan = "#".$chan unless($chan =~ m/^\#/); # Append # if doesn't begin with.
        warn "* Joining $chan\n";
        $self->send_server_unsafe (JOIN => $chan);
    }

    # When connecting, sometimes if a nick is in use it requires an alternative.
    my $nick_change = sub {
        my ($badnick) = @_;
        $self->{nick} .= "_";
        return $self->{nick};
    };

    $self->{con}->ctcp_auto_reply ('VERSION', ['Hadouken']);

    $self->{con}->set_nick_change_cb($nick_change);

    #$self->send_server_unsafe(PRIVMSG => "\*status","ClearAllChannelBuffers");

    #warn $self->{nick};
    #warn $server_hashref->{$server_name}{nickname};

    if($self->{nick} ne $server_hashref->{$server_name}{nickname} ) {
        $self->send_server_unsafe (NICK => $self->{nick});
    }


    $self->{con}->connect ($server_hashref->{$server_name}{host}, $server_hashref->{$server_name}{port},
        { iface => $self->{iface}, bindaddr => $self->{bind},
            real => 'hadouken',nick => $server_hashref->{$server_name}{nickname}, password => $server_hashref->{$server_name}{password}, send_initial_whois => 1});

    #     sub {
    #        my ($fh) = @_;

    #        exit(0);
    #        warn "BINDING TO LOCALHOST";
    #        $fh->bind("localhost");
    #},
    #);
# ident,quote,channel,time


    $self->{c}->wait unless $self->{reconnecting};

    #return 1;
}


sub normalize_mask {
    my ($self, $arg) = @_;
    return unless $arg;

    $arg =~ s/\*{2,}/*/g;
    my @mask;
    my $remainder;
    if ($arg !~ /!/ and $arg =~ /@/) {
        $remainder = $arg;
        $mask[0] = '*';
    }
    else {
        ($mask[0], $remainder) = split /!/, $arg, 2;
    }

    $remainder =~ s/!//g if defined $remainder;
    @mask[1..2] = split(/@/, $remainder, 2) if defined $remainder;
    $mask[2] =~ s/@//g if defined $mask[2];

    for my $i (1..2) {
        $mask[$i] = '*' if !defined $mask[$i];
    }
    return $mask[0] . '!' . $mask[1] . '@' . $mask[2];
}

sub matches_mask {
    my ($self, $mask, $match, $mapping) = @_;
    return if !defined $mask || !length $mask;
    return if !defined $match || !length $match;

    my $umask = quotemeta $self->uc_irc($mask, $mapping);
    $umask =~ s/\\\*/[\x01-\xFF]{0,}/g;
    $umask =~ s/\\\?/[\x01-\xFF]{1,1}/g;
    $match = $self->uc_irc($match, $mapping);

    return 1 if $match =~ /^$umask$/;
    return;
}

sub uc_irc {
    my ($self, $value, $type) = @_;
    return if !defined $value;
    $type = 'rfc1459' if !defined $type;
    $type = lc $type;

    if ($type eq 'ascii') {
        $value =~ tr/a-z/A-Z/;
    }
    elsif ($type eq 'strict-rfc1459') {
        $value =~ tr/a-z{}|/A-Z[]\\/;
    }
    else {
        $value =~ tr/a-z{}|^/A-Z[]\\~/;
    }

    return $value;
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

sub _asyncsock {
    my $self = shift;

    unless(defined $self->{asyncsock} ) {

        $self->{asyncsock} = AsyncSocket->new();

        require HTTP::Cookies;
        $self->{asyncsock}->cookie_jar(HTTP::Cookies->new);
    }

    return $self->{asyncsock};
}


sub _shorten {
    my $self = shift;
    my $url = shift;
    my $get_title = shift || 0;

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

            if($get_title) {
                my $response = $self->_webclient->get($url);

                my $p = HTML::TokeParser->new( \$response->decoded_content );

                if ($p->get_tag("title")) {
                    $title = $p->get_trimmed_text;
                    $title =~ s/[^[:ascii:]]+//g;
                }
            }

        }
    }
    catch($e) {
        $shortenurl = '';
        $title = '';
        warn "Error occured at shorten with url $url - $e";
    }

    return ($shortenurl,$title);
}

sub checkcookie {
    my ($self,$opped,$opper,$channel,$cookie) = @_;

    my $iv = substr(sha3_256_hex($self->{keys}{all}->[0]),0,8);
    my $cipher = Crypt::CBC->new(-cipher => 'Blowfish', -key => $self->{keys}{all}->[0],-iv => $iv, -header => 'none');
    my ($header,$hash) = split(/\@/,$cookie);
    my $ciphertext = MIME::Base64::decode_base64($hash);
    my $cleartext = $cipher->decrypt($ciphertext);
    my @parts = split(/ /,$cleartext);
    my $ts = substr $parts[2],-4;
    my $chname = substr $parts[2],0, (length($parts[2]) - 4);

    if($parts[0] eq $opped && $parts[1] eq $opper && $chname eq $channel) {
        return 1;
    }

    return 0;
}

sub makecookie {
    my ($self,$opped,$opper,$channel) = @_;

    my $ts = substr(time(),0,4);
    my $cookie_op;
    $cookie_op .= $opped;
    $cookie_op .= " ";
    $cookie_op .= $opper;
    $cookie_op .= " ";
    $cookie_op .= $channel;
    $cookie_op .= $ts;

    my $iv = substr(sha3_256_hex($self->{keys}{all}->[0]),0,8);
    my $cipher = Crypt::CBC->new(-cipher => 'Blowfish', -key => $self->{keys}{all}->[0],-iv => $iv, -header => 'none');
    my $cookie_op_encrypted = $cipher->encrypt( $cookie_op );
    my $cookie_op_inflated = MIME::Base64::encode_base64($cookie_op_encrypted);
    my $cookie = sprintf("%s!%s@%s",randstring(2),randstring(3),$cookie_op_inflated);

    # Just incase.
    $cookie =~ s/^\s+//;
    $cookie =~ s/\s+$//;
    $cookie =~ s/\n//g;
    return $cookie;
}

sub _chat_encrypt {
    my ($self,$who,$text) = @_;
    my $key = exists $self->{keys}{$who} ? $self->{keys}{$who}->[0] : $self->{keys}{all}->[0];
    return $self->_encrypt($text,$key);
}

sub _chat_decrypt {
    my ($self,$who,$text) = @_;
    my $key = exists $self->{keys}{$who} ? $self->{keys}{$who}->[0] : $self->{keys}{all}->[0];
    return $self->_decrypt($text,$key);
}

sub _encrypt {
    my ( $self, $text, $key ) = @_;
    
    $text =~ s/(.{8})/$1\n/g;
    my $result = '';
    try {
        my $cipher = new Crypt::Blowfish $key;
        foreach ( split /\n/, $text ) {
            $result .= $self->_inflate( $cipher->encrypt($_) );

        }
    } catch($e) {
    }
    return $result;
}

sub _decrypt {
    my ( $self, $text, $key ) = @_;
   
    $text =~ s/(.{12})/$1\n/g;
    my $result = '';
    my $cipher = new Crypt::Blowfish $key;
    #my $cipher = Crypt::CBC->new(-key => $key, -cipher => 'Blowfish');
    foreach ( split /\n/, $text ) {
        $result .= $cipher->decrypt( $self->_deflate($_) );
    }

    return $result;
}


sub _set_key {
    my ( $self, $user, $key ) = @_;

    $self->{keys}{$user} = [ $key, $key ];

    my $l = length($key);

    if ( $l < 8 ) {
        my $longkey = '';
        my $i       = 8 / $l;
        $i = $1 + 1 if $i =~ /(\d+)\.\d+/;
        while ( $i > 0 ) {
            $longkey .= $key;
            $i--;
        }
        $self->{keys}{$user} = [ $longkey, $key ];
    }
}

sub _inflate {
    my ( $self, $text ) = @_;
    my $result = '';
    my $k      = -1;

    while ( $k < ( length($text) - 1 ) ) {
        my ( $l, $r ) = ( 0, 0 );
        for ( $l, $r ) {
            foreach my $i ( 24, 16, 8 ) {
                $_ += ord( substr( $text, ++$k, 1 ) ) << $i;
            }
            $_ += ord( substr( $text, ++$k, 1 ) );
        }
        for ( $r, $l ) {
            foreach my $i ( 0 .. 5 ) {
                $result .= substr( B64, $_ & 0x3F, 1 );
                $_ = $_ >> 6;
            }
        }
    }
    return $result;
}

sub _deflate {
    my ( $self, $text ) = @_;
    my $result = '';
    my $k      = -1;

    while ( $k < ( length($text) - 1 ) ) {
        my ( $l, $r ) = ( 0, 0 );
        for ( $r, $l ) {
            foreach my $i ( 0 .. 5 ) {
                $_ |= index( B64, substr( $text, ++$k, 1 ) ) << ( $i * 6 );
            }
        }

        for ( $l, $r ) {
            foreach my $i ( 0 .. 3 ) {
                $result .= chr( ( $_ & ( 0xFF << ( ( 3 - $i ) * 8 ) ) ) >> ( ( 3 - $i ) * 8 ) );
            }
        }
    }

    return $result;
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


