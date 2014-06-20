package Hadouken::Configuration;

use strict;
use warnings;

our $VERSION = '0.1';
our $AUTHOR = 'dek';

use Moose;

use Redis;


has redis => (is => 'rw', isa => 'Redis', default => sub { my $redis = Redis->new(server => '127.0.0.1:6379'); $redis; });

sub new {
    my $class = shift;
    my $self = {@_};
    bless $self, $class;
    return $self;
}

#__PACKAGE__->meta->make_immutable;

1;

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

# 
# use 5.014;

our $VERSION = '0.5';
our $AUTHOR = 'dek';

use Data::Printer alias => 'Dumper', colored => 1;
#use Data::Dumper;

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

$Net::Whois::Raw::CHECK_FAIL = 1;

use HTML::TokeParser;
use URI ();
use LWP::UserAgent ();
use Encode qw( encode decode );
use Encode::Guess;

#use JSON::XS qw( encode_json decode_json );
use JSON; # qw( encode_json decode_json );
use POSIX qw(strftime);
use Time::HiRes qw( sleep );
use Geo::IP;
use Tie::Array::CSV;
use Regexp::Common;
use String::IRC;
use Net::Whois::IP ();
use Crypt::RSA;
use Convert::PEM;
use MIME::Base64 ();
use Crypt::OpenSSL::RSA;
use Crypt::Blowfish_PP;
use Crypt::DH;
use Crypt::CBC;

use Math::BigInt;
use Config::General;
use Time::Elapsed ();
use TryCatch;
use Config::General;
use Crypt::Random;

use Redis;
use Redis::List;

#use IO::Compress::Gzip qw(gzip $GzipError);
use Digest::SHA3 qw(sha3_256_hex);

use IRC::Utils ':ALL';

use Moose;

with 'MooseX::Getopt::GLD' => { getopt_conf => [ 'pass_through' ] };

use namespace::autoclean;

use File::Spec;
use FindBin qw($Bin);
use Module::Pluggable search_dirs => [ "$Bin/plugins/" ], sub_name => '_plugins';

#has asyncsock => (is => 'rw', isa => 'AsyncSocket', default => sub { my $as = AsyncSocket->new; return $as; });

has start_time => (is => 'ro', isa => 'Str', writer => '_set_start_time');
has connect_time => (is => 'ro', isa => 'Str', writer => '_set_connect_time');
has safe_delay => (is => 'rw', isa => 'Str', required => 0, default => '0.25');
has quote_limit => (is => 'rw', isa => 'Str', required => 0, default => '3');

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

my @commands = (
    {name => 'trivstop',       regex => 'trivstop$',               comment => 'stop trivia bot',                require_admin => 1 }, 
    {name => 'trivstart',      regex => 'trivstart$',              comment => 'start trivia bot',               require_admin => 1 }, 
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
    {name => 'ipcalc',         regex => 'ipcalc\s.+?',             comment => 'calculate ip netmask' },
    {name => 'calc',           regex => 'calc\s.+?',               comment => 'google calculator' },
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
    {name => 'plugins',        regex => 'plugins$',                comment => 'display list of available plugins' },
    {name => 'help',           regex => 'help$',                   comment => 'get help info' },
    {name => 'availableplugins', regex => 'availableplugins$',                comment => 'list all available plugins', require_admin => 1 },
    {name => 'loadplugin',        regex => 'loadplugin\s.+?',                comment => 'load plugin', require_admin => 1 },
    {name => 'unloadplugin',        regex => 'unloadplugin\s.+?',                comment => 'unload plugin', require_admin => 1 },
);

# TODO: Whois command, finish up

sub new {
    my $class = shift;
    my $self = {@_};
    bless $self, $class;
    return $self;
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


sub load_plugin {
    my ($self, $plugin_name) = @_;
    
    for my $plugin ($self->available_modules) {

        #next unless $plugin =~ $plugin_name;

        # Try unloading first ?
        # $self->unload_plugin($plugin);

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

        #$self->_plugin($plugin) = $m;

        $self->loaded_plugins->{$plugin} = $m;

        my $ver = $m->VERSION || '0.0';

        push @{$self->{plugin_regexes}}, {name => "$plugin", regex => "$command_regex"};

        warn "Plugin $plugin $ver added successfully.\n";
    }


    return 1;
}

sub unload_plugin {
    my ($self, $plugin_name) = @_;

    foreach my $plugin (keys %{$self->loaded_plugins}) { 
        next unless ($plugin eq $plugin_name); # EXACT MATCH ONLY!

        my $r = $self->unload_class('Hadouken::Plugin::'.$plugin);

        warn "** UNLOADING PLUGIN $plugin, r is $r";

        my $x = List::MoreUtils::first_index { $_->{name} eq $plugin_name } @{$self->{plugin_regexes}};

        splice @{$self->{plugin_regexes}}, $x, 1 if $x > -1;
        
        warn Dumper @{$self->{plugin_regexes}};

        delete $self->loaded_plugins->{$plugin};
        
    }

    return 1;
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

# Maybe add in config file watching and reload?
#
sub reload_config {
    my ($self) = @_;

    my $ret = 0;

    try {
        my $config_filename = $self->{config_filename};
        my $conf = Config::General->new(-ForceArray => 1, -ConfigFile => $config_filename, -AutoTrue => 1);                                                   
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

sub dh_key_exchange {
    my ($self,$user,$key) = @_;

    return;

    my $dh = Crypt::DH->new;

    my $g=0;
    while ($g<2){$g=int(rand(10));}

    $dh->g($g);
    my $p = $self->generate_prime;
    $dh->p($p);

    $dh->generate_keys;

    my $my_pub_key = $dh->pub_key;
    my $my_priv_key = $dh->priv_key;


    my $decoded_key = MIME::Base64::decode_base64($key);

    my $binstring = unpack('B*',pack ('a*', $decoded_key));

    my $shared_secret = $dh->compute_secret( $binstring );

    my $tempkey = unpack('B*',pack ('a*', $my_priv_key));

    my $shared_bin = unpack('B*',pack ('a*', $shared_secret));    

    $self->_set_key('all',$shared_secret);

    #warn $shared_bin;

    my $public_bin = unpack('B*',pack ('a*', $my_pub_key));

    my $enc_key = MIME::Base64::encode_base64($my_pub_key,'');

    warn $enc_key,"\n";

    my $dhfinish = 'DH1080_FINISH '. $enc_key;

    $self->send_server_unsafe(NOTICE => $user, $dhfinish);

    #warn "* Shared secret $shared_secret\n";

}

sub generate_prime {
    my ($self) = @_;

    my $p = new Math::BigInt('0');

    do {
        # generate a random number composed of random binary digits
        my $i=1;
        my $n="";
        while ($i<=254){
            $n=$n.int(rand(2));
            $i++;
        }
        # add 1 at the beginning and the end of n
        # then $n is big and odd
        $n = "1".$n."1";

        # convert n into a bigint via binary conversion
        my $bign = new Math::BigInt('0');
        foreach my $i (1..256){
            if(substr($n,-$i,1) eq '1'){$bign->badd(2**($i-1));}
        }

        my $temoin = new Math::BigInt('2');
        if ($temoin->bmodpow(($bign-1),$bign) == 1){
            $temoin->bone();$temoin->bmul(3);
            if ($temoin->bmodpow(($bign-1),$bign) == 1){
                $temoin->bone();$temoin->bmul(5);
                if ($temoin->bmodpow(($bign-1),$bign) == 1){
                    $temoin->bone();$temoin->bmul(7);
                    if ($temoin->bmodpow(($bign-1),$bign) == 1){
                        $p->bone();
                        $p->bmul($bign);
                    }
                }
            }
        }

    } while ($p == 0);    


    return $p;
}


sub readPrivateKey {
    my ($self,$file,$password) = @_;
    my $key_string;

    if (!$password) {
        open(PRIV,$file) || die "$file: $!";
        read(PRIV,$key_string, -s PRIV); # Suck in the whole file
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

    #my $wee = $self->_plugin("StockTicker") if(defined $self->_plugin("StockTicker"));

    $self->{plugin_regexes} = ();

    foreach my $plugin (keys %{$self->loaded_plugins}) { 
        my $mod = $self->_plugin($plugin);
        my $rx = $mod->command_regex;
        push @{$self->{plugin_regexes}}, {name => "$plugin", regex => $rx};
    }


    $self->unload_plugin('ExamplePlugin');

    if( $self->{private_rsa_key_filename} ne '' ) {
        my $key_string = $self->readPrivateKey($self->{private_rsa_key_filename}, $self->{private_rsa_key_password} ne '' ? $self->{private_rsa_key_password} : undef );
        $self->{_rsa} = Crypt::OpenSSL::RSA->new_private_key($key_string);
    }

    $self->{c} = AnyEvent->condvar;
    $self->{con} = AnyEvent::IRC::Client->new();

    $self->_start;
}

before 'send_server_safe' => sub {
    my $self = shift;

    Time::HiRes::sleep($self->safe_delay);
};

before 'send_server_long_safe' => sub {
    my $self = shift;

    Time::HiRes::sleep($self->safe_delay);
};

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

sub channel_add {
    my ($self, $channel) = @_;

    my $conf = $self->{config_hash};
    my $server_name = $self->{server_name};

    $channel =~ s/^\#//;
    $conf->{server}{$server_name}{channel}{$channel}{shorten_urls} = 0;
    $conf->{server}{$server_name}{channel}{$channel}{op_admins} = 0;
    $conf->{server}{$server_name}{channel}{$channel}{protect_admins} = 0;

    $self->{conf_obj}->save_file($self->{config_filename}, $conf);

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

    $self->{conf_obj}->save_file($self->{config_filename}, $conf);

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

    push($self->{quotesdb},$row);
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

    # We can push first value to prevent unneeded -1 check
    my $new_array = [shift @$array];
    foreach (@$array) {
        push @$new_array, $_ unless $_ eq $new_array->[-1];
    }

    return $new_array;
}

sub blacklisted {
    my ($self, $who) = @_;
    my ($nick,$host) = $self->get_nick_and_host($who);

    $nick = lc($nick);
    $host = lc($host);

    if(grep { $_->[0] eq '*' ? lc($_->[1]) eq $host: lc($_->[0]) eq $nick && lc($_->[1]) eq $host } @{$self->{blacklistdb}}) {
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

    if(grep { $_->[0] eq '*' ? lc($_->[1]) eq $host : lc($_->[1]) eq $host && lc($_->[0]) eq $nick } @{$self->{adminsdb}}) {
        # warn "* Wildcard matching !\n";
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
    my $self = shift;

    my ($string) = @_;
    return if !defined $string;

    # mIRC colors
    $string =~ s/\x03(?:,\d{1,2}|\d{1,2}(?:,\d{1,2})?)?//g;

    # RGB colors supported by some clients
    $string =~ s/\x04[0-9a-fA-F]{0,6}//g;

    # see ECMA-48 + advice by urxvt author
    $string =~ s/\x1B\[.*?[\x00-\x1F\x40-\x7E]//g;

    # strip cancellation codes too if there are no formatting codes
    $string =~ s/\x0f//g if !$self->_has_formatting($string);
    return $string;
}

sub _filter_colors {
    my $self = shift;
    my ($line) = @_;
    $line =~ s/\x1B\[.*?[\x00-\x1F\x40-\x7E]//g; # see ECMA-48 + advice by urxvt author
    $line =~ s/\x03\d\d?(?:,\d\d?)?//g;          # see http://www.mirc.co.uk/help/color.txt
    $line =~ s/[\x03\x16\x02\x1f\x0f]//g;        # see some undefined place :-)
    return $line;
}

sub _strip_formatting {
    my $self = shift;
    my ($string) = @_;
    return if !defined $string;
    $string =~ s/[\x02\x1f\x16\x1d\x11\x06]//g;

    # strip cancellation codes too if there are no color codes
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
    #return unless $self->{hexdump};

    my ($label,$data);
    if (scalar(@_) == 2) {
        $label = shift;
    }
    $data = shift;

    print "$label:\n" if ($label);

    # Show 16 columns in a row.
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

        if ($col == 8) {
            print "  ";
        }
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
        if ($col == 8) {
            print "  ";
        }
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

    #my $redis = Redis->new;

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
        push($self->{adminsdb}, @admin_row);
    }

    my $func_flags = sub {
        my ($who, $message, $channel, $channel_list) = @_;

        { use integer;

            my $userFlags = pack('b8','00001100');

            $userFlags = $self->addFlag($userFlags, BIT_ADMIN) if($self->is_admin($who));
            $userFlags = $self->addFlag($userFlags, BIT_BLACKLIST) if($self->blacklisted($who));
            $userFlags = $self->addFlag($userFlags, BIT_WHITELIST) if($self->whitelisted($who));

            if(defined $channel_list) {
                my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

                if(exists $channel_list->{$nickname}) {
                    $userFlags = $self->addFlag($userFlags, BIT_OP) if(/o$/ ~~ $channel_list->{$nickname});
                    $userFlags = $self->addFlag($userFlags, BIT_VOICE) if(/v$/ ~~ $channel_list->{$nickname});
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

    $self->add_func(name => 'trivstart',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

            return unless defined $channel;

            #$self->send_server_unsafe(PRIVMSG => $channel, "  Starting trivia!");

            $self->_start_trivia($channel);

            return 1;
        },
        acl => $admin_access
    );

    $self->add_func(name => 'trivstop',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

            #return unless defined $channel;

            #$self->send_server_unsafe(PRIVMSG => $channel, "  Starting trivia!");

            $self->_stop_trivia;

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
                $self->send_server_unsafe( MODE => $channel, '+o', $nickname);
            }

            return 1;
        },
        acl => $admin_access
    );

    $self->add_func(name => 'channeldel',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
            my ($cmd, $arg) = split(/ /, $message, 2);

            return unless ((defined $arg) && ($self->{con}->is_channel_name($arg)));

            $self->channel_del($arg);

            return 1;
        },
        acl => $admin_access,
    );

    $self->add_func(name => 'channeladd',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
            my ($cmd, $arg) = split(/ /, $message, 2);

            return unless ((defined $arg) && ($self->{con}->is_channel_name($arg)));

            $self->channel_add($arg);

            return 1;
        },
        acl => $admin_access,
    );

    $self->add_func(name => 'admindel',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
            my ($cmd, $arg) = split(/ /, lc($message), 2);

            return unless defined $arg;

            my $del_ret = $self->admin_delete($who, $arg);

            if($del_ret) {
                my $out_msg = "[admindel] deleted admin $arg -> by $nickname";

                my $msg = sprintf '+OK %s', $self->_encrypt( $out_msg, $self->{keys}->[0] );

                $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
            }

            return 1;
        },
        acl => $admin_access,
    );

    $self->add_func(name => 'adminadd',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
            my ($cmd, $arg) = split(/ /, lc($message), 2);

            return unless defined $arg;

            my $add_ret = $self->admin_add($who, $arg);

            if($add_ret) {
                my $out_msg = '[adminadd] added admin '.$arg.' - > by '.$nickname;

                my $msg = sprintf '+OK %s', $self->_encrypt( $out_msg, $self->{keys}->[0] );

                $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
            }

            return 1;
        },
        acl => $admin_access,
    );

    $self->add_func(name => 'whitelistadd',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
            my ($cmd, $arg) = split(/ /, lc($message), 2);

            return unless defined $arg;

            my $add_ret = $self->whitelist_add($who, $arg);

            if($add_ret) {
                my $out_msg = "[whitelistadd] added whitelist $arg -> by $nickname";
                my $msg = sprintf '+OK %s', $self->_encrypt( $out_msg, $self->{keys}->[0] );

                $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
            }

            return 1;
        },
        acl => $admin_access,
    );


    $self->add_func(name => 'whitelistdel',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;

            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

            my ($cmd, $arg) = split(/ /, lc($message), 2);

            return unless defined $arg;

            my $del_ret = $self->whitelist_delete($who, $arg);

            if($del_ret) {
                my $out_msg = "[whitelistdel] deleted whitelist $arg -> by $nickname";

                my $msg = sprintf '+OK %s', $self->_encrypt( $out_msg, $self->{keys}->[0] );

                $self->send_server_unsafe (PRIVMSG => $nickname, $out_msg);

            }

            return 1;
        },
        acl => $admin_access,
    );

    $self->add_func(name => 'blacklistadd',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
            my ($cmd, $arg) = split(/ /, lc($message), 2);

            return unless defined $arg;

            my $add_ret = $self->blacklist_add($who, $arg);

            if($add_ret) {
                my $out_msg = "[blacklistadd] added blacklist $arg -> by $nickname";

                my $msg = sprintf '+OK %s', $self->_encrypt( $out_msg, $self->{keys}->[0] );

                $self->send_server_unsafe (PRIVMSG => $nickname, $out_msg);

            }

            return 1;
        },
        acl => $admin_access,
    );


    $self->add_func(name => 'blacklistdel',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;

            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

            my ($cmd, $arg) = split(/ /, lc($message), 2);

            return unless defined $arg;

            my $del_ret = $self->blacklist_delete($who, $arg);

            if($del_ret) {
                my $out_msg = "[blacklistdel] deleted blacklist $arg -> by $nickname";

                my $msg = sprintf '+OK %s', $self->_encrypt( $out_msg, $self->{keys}->[0] );

                $self->send_server_unsafe (PRIVMSG => $nickname, $out_msg);
            }

            return 1;
        },
        acl => $admin_access,
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

    $self->add_func(name => 'shorten',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

            my ($cmd, $arg) = split(/ /, $message, 2); # DO NOT LC THE MESSAGE!

            return unless defined $arg;

            my ($uri) = $arg =~ /$RE{URI}{HTTP}{-scheme=>'https?'}{-keep}/;

            return 0 unless defined $uri;

            # Only grab title for admins.
            my ($url,$title) = $self->_shorten($uri,$self->is_admin($who));

            if(defined $url && $url ne '') {
                if(defined $title && $title ne '') {
                    $self->send_server_unsafe (PRIVMSG => $channel, "$url ($title)");
                } else {
                    $self->send_server_unsafe (PRIVMSG => $channel, "$url");   
                }
            }

            return 1;
        },
        acl => $passive_access
    );

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

                $self->send_server_unsafe (PRIVMSG => $channel, $out_msg);
            } elsif($netbit =~ /$RE{net}{IPv4}/) {

                my $cidr = $self->netmask2cidr($netbit,$network);

                my $poop = "[ipcalc] $arg -> cidr $cidr";

                $self->send_server_unsafe (PRIVMSG => $channel, $poop);
            }

            return 1;
        },
        acl => $passive_access,
    );

    $self->add_func(name => 'calc',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;

            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

            my ($cmd, $arg) = split(/ /, lc($message), 2);

            return unless (defined($arg) && length($arg));

            my $res_calc = $self->calc($arg);

            return unless defined $res_calc;

            $self->send_server_unsafe (PRIVMSG => $channel, "[calc] $res_calc");

            return 1;
        },
        acl => $passive_access,
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

                $self->send_server_unsafe (PRIVMSG => $channel, $ip_result);           

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
                            $self->send_server_unsafe (PRIVMSG => $channel, "$arg ($ip_addr) -> no results in db");
                            return;
                        }

                        my $dom_result = "$arg ($ip_addr) ->";
                        $dom_result .= " City:".$record->city if defined $record->city && $record->city ne '';
                        $dom_result .= " Region:".$record->region if defined $record->region && $record->region ne '';
                        $dom_result .= " Country:".$record->country_code if defined $record->country_code && $record->country_code ne '';

                        $self->send_server_unsafe (PRIVMSG => $channel, $dom_result);           
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
                                $self->send_server_unsafe (PRIVMSG => $channel, "$arg ($ip_addr) -> no results in db");
                                return;
                            }

                            my $dom_result = "$arg ($ip_addr) ->";
                            $dom_result .= " City:".$record->city if defined $record->city && $record->city ne '';
                            $dom_result .= " Region:".$record->region if defined $record->region && $record->region ne '';
                            $dom_result .= " Country:".$record->country_code if defined $record->country_code && $record->country_code ne '';

                            $self->send_server_unsafe (PRIVMSG => $channel, $dom_result);
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
        acl => $all_access_except_blacklist,
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


            $self->send_server_unsafe (NOTICE => $nickname, $si1);
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


                $self->send_server_unsafe (NOTICE => $nickname, $command_summary);
                #$self->send_server_long_safe ("PRIVMSG\001ACTION", $nickname, $command_summary);
                #$self->send_server_unsafe (PRIVMSG => $nickname, $command_summary);
                undef $command_summary;
            }
            undef $iter;

            return 1;
        },
        acl => $all_access_except_blacklist,
    );


    $self->add_func(name => 'plugins',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

            my $si1 = String::IRC->new('Available Plugins:')->bold;
            $self->send_server_unsafe (NOTICE => $nickname, $si1);

            try { # Plugins can be unpredictable.
                foreach my $plugin (keys %{$self->loaded_plugins}) { 
                    my $command_summary = '';
                    my $p = $self->_plugin($plugin);

                    my $name = $p->command_name;
                    my $comment = $p->command_comment || '';
                    my $ver = $p->VERSION || '0.0';

                    my $si = String::IRC->new($name)->bold;
                    $command_summary .= '['.$si.'] '.$ver.' -> '.$comment." ";
                   
                   
                    $self->send_server_unsafe (NOTICE => $nickname, $command_summary);
                
                }
            }
            catch($e) {
            }

            return 1;
        },
        acl => $all_access_except_blacklist,
    );

    $self->add_func(name => 'availableplugins',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);

            my $si1 = String::IRC->new('All Available Plugins:')->bold;
            $self->send_server_unsafe (NOTICE => $nickname, $si1);


            # We do this because of central installed and locally installed modules.
            my @avail = $self->available_modules();
            my $x = _->unique(\@avail,0);

            try { # Plugins can be unpredictable.
                for my $plugin (@$x) {
                    my $command_summary = '';
                    my $is_loaded = exists $self->loaded_plugins->{$plugin} ? "yes" : "no";
                    $command_summary .= "[$plugin] Loaded: $is_loaded ";

                    $self->send_server_unsafe (NOTICE => $nickname, $command_summary);
                }
            }
            catch($e) {
            }

            return 1;
        },
        acl => $admin_access,
    );

    $self->add_func(name => 'loadplugin',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
            my ($cmd, $arg) = split(/ /, $message, 2);

            return unless defined $arg;

            my $plugin_name = '';
            if ( defined($plugin_name = List::MoreUtils::first_value { $arg eq $_ } $self->available_modules) ) {

                return if exists $self->loaded_plugins->{$plugin_name};
                
                my $added_ok = $self->load_plugin($plugin_name);
    
                return unless ($added_ok);
                my $out_msg = '[loadplugin] loaded plugin '.$arg.' - > by '.$nickname;

                my $msg = sprintf '+OK %s', $self->_encrypt( $out_msg, $self->{keys}->[0] );

                $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
            }

            return 1;
        },
        acl => $admin_access,
    );
    
    $self->add_func(name => 'unloadplugin',
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
            my ($cmd, $arg) = split(/ /, $message, 2);

            return unless defined $arg;

            my $plugin_name = '';
            if ( defined($plugin_name = List::MoreUtils::first_value { $arg eq $_ } $self->available_modules) ) {

                #return if exists $self->loaded_plugins->{$plugin_name};

                my $unloaded_ok = $self->unload_plugin($plugin_name);

                return unless ($unloaded_ok);
                my $out_msg = '[unloadplugin] unloaded plugin '.$arg.' - > by '.$nickname;

                my $msg = sprintf '+OK %s', $self->_encrypt( $out_msg, $self->{keys}->[0] );

                $self->send_server_unsafe (PRIVMSG => $nickname, $msg);
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
            my $si = String::IRC->new('Hi '.$nickname.', type .commands in the channel.')->bold;
            $self->{con}->send_long_message ("utf8", 0, "PRIVMSG\001ACTION", $nickname, $si);
            # $self->send_server_unsafe (PRIVMSG => $nickname, $si);

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
            my $msg = sprintf '+OK %s', $self->_encrypt( $basic_info, $self->{keys}->[0] );
            $self->send_server_unsafe (PRIVMSG => $nickname, $msg);

            return 1;
        },
        acl => $admin_access,
    );

    $self->add_func(name => 'btc', 
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my ($mode_map,$nickname,$ident) = $self->{con}->split_nick_mode($who);
            my $json = $self->fetch_json('https://btc-e.com/api/3/ticker/btc_usd');
            my $json2 = $self->fetch_json('https://crypto-trade.com/api/1/ticker/btc_usd');
            my $ret =  "[btc_usd\@btce] Last: $json->{btc_usd}->{last} Low: $json->{btc_usd}->{low} High: $json->{btc_usd}->{high} Avg: $json->{btc_usd}->{avg} Vol: $json->{btc_usd}->{vol}";
            my $ret2 = "[btc_usd\@ct]   Last: $json2->{data}->{last} Low: $json2->{data}->{low} High: $json2->{data}->{high} Vol(usd): $json2->{data}->{vol_usd}";
            $self->send_server_unsafe (PRIVMSG => $channel, $ret);
            $self->send_server_unsafe (PRIVMSG => $channel, $ret2);

            return 1;
        },
        acl => $admin_access,
    );

    $self->add_func(name => 'ltc', 
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my $json = $self->fetch_json('https://btc-e.com/api/3/ticker/ltc_usd');
            my $json2 = $self->fetch_json('https://crypto-trade.com/api/1/ticker/ltc_usd');
            my $ret =  "[ltc_usd\@btce] Last: $json->{ltc_usd}->{last} Low: $json->{ltc_usd}->{low} High: $json->{ltc_usd}->{high} Avg: $json->{ltc_usd}->{avg} Vol: $json->{ltc_usd}->{vol}";
            my $ret2 = "[ltc_usd\@ct]   Last: $json2->{data}->{last} Low: $json2->{data}->{low} High: $json2->{data}->{high} Vol(usd): $json2->{data}->{vol_usd}";

            $self->send_server_unsafe (PRIVMSG => $channel, $ret);
            $self->send_server_unsafe (PRIVMSG => $channel, $ret2);

            return 1;
        },
        acl => $admin_access,
    );

    $self->add_func(name => 'eur2usd', 
        delegate => sub {
            my ($who, $message, $channel, $channel_list) = @_;
            my $json = $self->fetch_json('https://btc-e.com/api/3/ticker/eur_usd');
            my $ret = "[eur_usd] Last: $json->{eur_usd}->{last} Low: $json->{eur_usd}->{low} High: $json->{eur_usd}->{high} Avg: $json->{eur_usd}->{avg} Vol: $json->{eur_usd}->{vol}";
            $self->send_server_unsafe (PRIVMSG => $channel, $ret);

            return 1;
        },
        acl => $all_access_except_blacklist,
    );

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
            if($self->is_admin($ident)) {

                my $cur_channel_clean = $channel;
                $cur_channel_clean =~ s/^\#//;

                my $server_hash_ref = $self->{current_server};

                if(exists $server_hash_ref->{channel}{$cur_channel_clean} && $server_hash_ref->{channel}{$cur_channel_clean}{op_admins} == 1) {
                    $self->send_server_unsafe( MODE => $channel, '+o', $nick);   

                    # who was opped, who opped them, a timestamp


                    #opped opper channel

                    my $cookie = $self->makecookie($ident,$self->{nick},$channel);

                    my $test = $self->checkcookie($ident,$self->{nick},$channel,$cookie);
                    $self->send_server_unsafe( MODE => $channel, '-b', $cookie);

                    #warn "WEEEEE" if $test;
                    #warn $nick;
                    #warn $cookie;


                    #$self->{_rsa}->e
                }

                # $self->send_server_unsafe( MODE => $channel, '+o', $nick);   
            }
        },
        kick => sub {
            my($con, $kicked_nick, $channel, $is_myself, $msg, $kicker_nick) = (@_);
            warn "* KICK CALLED -> $kicked_nick by $kicker_nick from $channel with message $msg -> is myself: $is_myself!\n";
            # warn "my nick is ". $self->{con}->nick() ."\n";
            if($self->{con}->nick() eq $kicked_nick || $self->{con}->is_my_nick($kicked_nick)) {
                if($self->{rejoin_on_kick}) {
                    warn "* Rejoining $channel automatically\n";
                    $self->send_server_unsafe (JOIN => $channel);
                }
                # my $si = String::IRC->new($kicker_nick)->red->bold;
                # $self->send_server_unsafe (PRIVMSG => $channel,"kicked by $si, behavior logged");
            }
        },
        dcc_request => sub {
            my ($con, $id, $src, $type, $arg, $addr, $port) = @_;

            warn "* DCC Request from $addr\n";

            $self->{con}->dcc_accept($id);

            warn "* DCC Accepting\n";
        },
        dcc_chat_msg => sub {
            my ($con, $id, $msg) = @_;

            warn "* DCC CHAT MSG $msg\n";

            if ($msg =~ s/^\+OK //) {
                $msg = $self->_decrypt( $msg, $self->{keys}->[0] );
                $msg =~ s/\0//g;

                warn "* Decrypted $msg\n";

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
                        $message = $self->_decrypt( $message, $self->{keys}->[0] );
                        $message =~ s/\0//g;

                        warn "* Decrypted $message\n";

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

                my $uri = undef;

                if (( ($uri) = $message =~ /$RE{URI}{HTTP}{-scheme=>'https?'}{-keep}/ ) ) { #m{($RE{URI})}gos ) {
                    warn "* Matched a URL $uri\n";

                    my $cur_channel_clean = $channel;
                    $cur_channel_clean =~ s/^\#//;
                    my $server_hash_ref = $self->{current_server};

                    if(exists $server_hash_ref->{channel}{$cur_channel_clean} && $server_hash_ref->{channel}{$cur_channel_clean}{shorten_urls} == 1 ) {

                        warn "* shorten_urls IS set for this channel\n";

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
                    } else {
                        warn "* shorten_urls disabled for this channel\n";
                    }
                }

                # Try to match a plugin command last(but not least).

                my $clean_msg = AnyEvent::IRC::Util::filter_colors($message);
                my $user_admin = $self->is_admin($who);
                my $user_whitelisted = $self->whitelisted($who);


                # Regex is cached ahead of time
                for my $plugin_regex (@{$self->{plugin_regexes}}) {
                    my $plugin = $plugin_regex->{name};
                    my $regex = $plugin_regex->{regex};
                    if($clean_msg =~ /$command_prefix$regex/) {

                        $clean_msg =~ s/$command_prefix//g;

                        my $m = $self->_plugin($plugin); # lazy load plugin :)
                        #my $plugin_acl_ret = $m->acl_check($nickname, $ident, $clean_msg, $channel || undef,$user_admin,$user_whitelisted);
                        my $plugin_acl_ret = $m->acl_check( $plugin_acl_func->($who, $clean_msg, $channel || undef, $channel_list || undef) );

                        warn "* Plugin $plugin -> ACL returned $plugin_acl_ret\n";
                        if($plugin_acl_ret) {
                            warn "* Plugin $plugin -> Calling delegate\n";
                            my $cmd_ret = $m->command_run($nickname, $ident, $clean_msg, $channel || undef, $user_admin, $user_whitelisted);
                        }
                    }
                }


                if($channel eq '#trivia') {
                    if($nickname eq 'utonium') {

                        if($message =~ 'QUESTION' || $message =~ 'googled the answer' || $message =~ 'start giving answers like this one') {
                            my $stripped = $self->_decode_irc($message);

                            $stripped =~ s/\x03\x31.*?\x03/ /g;
                            $stripped =~ s/[\x20\x39]/ /g;
                            $stripped =~ s/[\x30\x2c\x31]//g;

                            #$stripped = $self->strip_formatting($stripped);

                            $stripped = $self->_strip_color($stripped);

                            $stripped =~ s/\h+/ /g;                            

                            $stripped .= "\n";

                            $self->hexdump("Unstripped",$stripped);

                            open(FILE,">>".$self->{ownerdir}.'/../data/new_questions_parsed');
                            print FILE $stripped;
                            close(FILE);
                        }
                    }
                }

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

                                #print Dumper($self->{_scores});

                                warn $self->{_scores}{$nickname}{score};

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

                                #warn "WTF";

                                my $pos_prev = $rankings[$user_rank - 2] || undef;
                                my $pos_next = $rankings[$user_rank + 2] || undef;

                                warn $pos_prev;
                                warn $pos_next;

                                if($user_rank == 1 && defined $pos_next) {
                                    my $points_ahead = $self->{_scores}{$nickname}{score} - $self->{_scores}{$pos_next}{score};
                                    my $first_place_msg = "  $nickname is $points_ahead points ahead for keeping 1st place!";
                                    #warn $first_place_msg;

                                    $self->send_server_unsafe(PRIVMSG => $self->{trivia_channel},$first_place_msg);

                                } else {
                                    if(defined $pos_prev) {
                                        my $points_needed = $self->{_scores}{$pos_prev}{score} - $self->{_scores}{$nickname}{score};
                                        my $position_message = "  $nickname needs $points_needed points to take over position ". $self->{_scores}{$pos_prev}{rank};

                                        #warn $position_message;

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
                        if($notice_msg  =~ 'DH1080_INIT') {
                            my ($h,$pubkey) = split(/ /,$notice_msg);
                            if(defined $pubkey && $pubkey ne '') {

                                warn "* Key Exchange Initialized\n";

                                $self->dh_key_exchange($nick,$pubkey);

                            }
                        }
                    }
                }

                if($cmd eq 'MODE') {
                    my ($chan, $modeset) = @{$msg->{params}};
                    if(defined $chan && $chan ne '' && $chan =~ /^#/ ) {
                        my $cur_channel_clean = $chan;
                        $cur_channel_clean =~ s/^\#//;

                        my $server_hash_ref = $self->{current_server};
                        if(exists $server_hash_ref->{channel}{$cur_channel_clean} && $server_hash_ref->{channel}{$cur_channel_clean}{protect_admins} == 1) {

                            my @x = List::MoreUtils::after { $_ =~ '-o' } @{$msg->{params}};

                            if(@x) {
                                my @admins = grep { $self->is_admin($con->nick_ident($_)) } @x;

                                if(@admins) {
                                    my $it = List::MoreUtils::natatime 3, @admins;

                                    while (my @vals = $it->()) {
                                        my $mode = '+';
                                        $mode .= 'o' x ($#vals + 1);

                                        warn "* Protect triggered in $chan, setting MODE $mode ".join('  ',@vals) ."\n";

                                        unshift(@vals,$mode);
                                        $self->send_server_unsafe( MODE => $chan, @vals);

                                        my $cookie = $self->makecookie($nick,$self->{nick},$chan);
                                        my $test = $self->checkcookie($nick,$self->{nick},$chan,$cookie);
                                        $self->send_server_unsafe( MODE => $chan, '-b', $cookie);
                                    }
                                }
                            }

                            my @bans = List::MoreUtils::after { $_ =~ /\+b/ } @{$msg->{params}};
                            if(@bans) {

                                unless($self->is_admin($ident)) {

                                    warn "* Protect triggered in $chan, UNBANNING ".join('  ',@bans) ."\n";
                                    foreach my $ban (@bans) {
                                        warn "UNBANNING $ban";
                                        $self->send_server_unsafe( MODE => $chan, '-b', $ban);
                                        $self->send_server_unsafe( MODE => $chan, '-o', $nick);
                                    }

                                } else {

                                    warn "* Admin is banning users in $chan, ".join('  ',@bans) ."\n";
                                    foreach my $ban (@bans) {

                                        my $n_ban = $self->normalize_mask($ban);

                                        # Admin can ban anyone except:


                                        # Admin can't ban other admins
                                        if(grep { $self->matches_mask($n_ban, $self->normalize_mask($_->[0].'@'.$_->[1]) ) } @{$self->{adminsdb}} ) {

                                            $self->send_server_unsafe( MODE => $chan, '-b', $ban);

                                            unless ($self->is_admin($ident)) {
                                                $self->send_server_unsafe( MODE => $chan, '-o', $nick);
                                            }
                                        }

                                        # Can't ban whitelisted!
                                        if(grep { $self->matches_mask($n_ban, $self->normalize_mask($_->[0].'@'.$_->[1]) ) } @{$self->{whitelistdb}} ) {

                                            $self->send_server_unsafe( MODE => $chan, '-b', $ban);

                                            unless ($self->is_admin($ident)) {
                                                $self->send_server_unsafe( MODE => $chan, '-o', $nick);
                                            }
                                        }
                                    }
                                }
                            }



                        }
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

    #print Dumper($self->{_scores});

    my @rankings = sort { $self->{_scores}->{$b}->{score} <=> $self->{_scores}->{$a}->{score} } keys $self->{_scores};


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
    my @servernames = keys $server_hashref;
    my $server_name = $servernames[0];

    $self->{current_server} = $server_hashref->{$server_name};
    $self->{server_name} = $server_name;
    my @channels = keys $server_hashref->{$server_name}{channel};

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

    $self->{con}->set_nick_change_cb($nick_change);

    #$self->send_server_unsafe(PRIVMSG => "\*status","ClearAllChannelBuffers");

    $self->{con}->connect ($server_hashref->{$server_name}{host}, $server_hashref->{$server_name}{port},
        { localaddr => 'he-ipv6', real => 'bitch',nick => $self->{nick}, password => $server_hashref->{$server_name}{password}, send_initial_whois => 1});

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

sub prep {
    my ($fh) = @_;
    warn "**** BINDING TO LOCALHOST";
    $fh->bind("localhost");
    $fh;
}

sub normalize_mask {
    my ($self, $arg) = @_;
    return if !defined $arg;

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

    my $iv = substr(sha3_256_hex($self->{keys}->[0]),0,8);

    my $cipher = Crypt::CBC->new(-cipher => 'Blowfish', -key => $self->{keys}->[0],-iv => $iv, -header => 'none');

    my ($header,$hash) = split(/\@/,$cookie);

    my $ciphertext = MIME::Base64::decode_base64($hash);

    my $cleartext = $cipher->decrypt($ciphertext);

    my @parts = split(/\t/,$cleartext);

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
    $cookie_op .= "\t";
    $cookie_op .= $opper;
    $cookie_op .= "\t";
    $cookie_op .= $channel;
    $cookie_op .= $ts;

    my $iv = substr(sha3_256_hex($self->{keys}->[0]),0,8);

    my $cipher = Crypt::CBC->new(-cipher => 'Blowfish', -key => $self->{keys}->[0],-iv => $iv, -header => 'none');

    my $cookie_op_encrypted = $cipher->encrypt( $cookie_op );

    my $cookie_op_inflated = MIME::Base64::encode_base64($cookie_op_encrypted);

    my $cookie = sprintf("%s!%s@%s",randstring(2),randstring(3),$cookie_op_inflated);


    return $cookie;
}

sub _encrypt {
    my ( $self, $text, $key ) = @_;

    $text =~ s/(.{8})/$1\n/g;
    my $result = '';
    #try {
    my $cipher = new Crypt::Blowfish_PP $key;
    foreach ( split /\n/, $text ) {
        $result .= $self->_inflate( $cipher->encrypt($_) );

    }
    #} catch($e) {
    #}
    return $result;
}

sub _decrypt {
    my ( $self, $text, $key ) = @_;

    $text =~ s/(.{12})/$1\n/g;
    my $result = '';
    #my $cipher = new Crypt::Blowfish_PP $key;
    my $cipher = Crypt::CBC->new(-key => $key, -cipher => 'Blowfish');
    foreach ( split /\n/, $text ) {
        $result .= $cipher->decrypt( $self->_deflate($_) );
    }

    return $result;
}

sub _set_key {
    my ( $self, $user, $key ) = @_;

    $self->{keys} = [ $key, $key ];

    my $l = length($key);

    if ( $l < 8 ) {
        my $longkey = '';
        my $i       = 8 / $l;
        $i = $1 + 1 if $i =~ /(\d+)\.\d+/;
        while ( $i > 0 ) {
            $longkey .= $key;
            $i--;
        }
        $self->{keys} = [ $longkey, $key ];
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


