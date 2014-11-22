package Hadouken::Plugin::UrbanDictionary;

use strict;
use warnings;

use String::IRC;
use URI::Escape;
use HTML::TokeParser;

#use Data::Printer alias => 'Dumper', colored => 1;

use TryCatch;

our $VERSION = '0.2';
our $AUTHOR = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return "urban dictionary lookup. no arguments for random definition.";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "urban";
}

sub command_regex {
    my $self = shift;

    return 'urban';
}

# Return 1 if OK.
# 0 if does not pass ACL.
sub acl_check {
    my ($self, %aclentry) = @_;

    my $permissions = $aclentry{'permissions'};
    #my $who = $aclentry{'who'};
    #my $channel = $aclentry{'channel'};
    #my $message = $aclentry{'message'};


    # Or you can do it with the function Hadouken exports.
    # Make sure at least one of these flags is set.
    if($self->check_acl_bit($permissions, Hadouken::BIT_ADMIN) 
        || $self->check_acl_bit($permissions, Hadouken::BIT_WHITELIST) 
        || $self->check_acl_bit($permissions, Hadouken::BIT_OP)) {

        return 1;
    }

    return 0;
}

# Return 1 if OK (and then callback can be called)
# Return 0 and the callback will not be called.
sub command_run {
    my ($self,$nick,$host,$message,$channel,$is_admin,$is_whitelisted) = @_;
    my ($cmd, $arg) = split(/ /, lc($message),2);

    my $parg = $arg;
    
    $parg =~ s/stankdick/luchi/gi;
    
    if(defined($arg) && length($arg)) {
        $arg =~ s/dave__/black american princess/gi;
        $arg =~ s/erb/homo/gi;
        $arg =~ s/luchinii/sword fight/gi;
        $arg =~ s/vapor/HNIC/gi;
        $arg =~ s/2f/dickcheese/gi;
        $arg =~ s/luchini/gook/gi;
        $arg =~ s/luchinii/gook/gi;
        $arg =~ s/luchi/gook/gi; #sword fight
        $arg =~ s/dek/Awesomatimistic/gi;
        $arg =~ s/mptank/boss/gi;
        $arg =~ s/dakuwan/boss/gi;
        $arg =~ s/nimrood/boss/gi;
        $arg =~ s/f8al/M8/gi;
        $arg =~ s/moe/politically challenged/gi;
        $arg =~ s/adminmike/nigger/gi;        
        $arg =~ s/frosty/el jefe/gi;
        $arg =~ s/yak/canadian hot pocket/gi;
        $arg =~ s/r0ach/canadian hot pocket/gi;
        $arg =~ s/subz/habitual bungler/gi;
    }
    
    my $get_random;
    my $urban_url;

    if(defined($arg) && length($arg)) {
        $urban_url = 'http://www.urbandictionary.com/define.php?term='. uri_escape($arg);
    } else {
        $get_random = 1;
        $urban_url = 'http://www.urbandictionary.com/random.php';
    }

    my $random_meaning = 'random';

    $self->asyncsock->get($urban_url, sub {
            my ($body, $header) = @_;

            return unless defined $body && defined $header;

            my $parser = HTML::TokeParser->new( \$body );

            if($get_random) {
            if ($parser->get_tag("title")) {
                $random_meaning = $parser->get_trimmed_text;
                $random_meaning =~ s/Urban Dictionary: //g;
                $parg = $random_meaning;
                $arg = $random_meaning;
            }
            }
            
            while (my $token = $parser->get_tag('div')) {
                next unless (defined $token->[1] && exists $token->[1]{'class'});

                my $c = $token->[1]{'class'};

                if($c =~ 'meaning') {
                    my $text = $parser->get_trimmed_text("/div");

                    last if $text eq '* Meaning';

                    if(length($text) > 500) {
                        $text = substr($text,1, 500);
                    }

                    my $arg_pretty = String::IRC->new($parg)->bold;                
                    my $ret = "[$arg_pretty] - $text";
                    $self->send_server (PRIVMSG => $channel, $ret);
                    last;
                }

            }
        });

    return 1;
}



1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Hadouken::Plugin::UrbanDictionary - Urban Dictionary plugin.

=head1 DESCRIPTION

Urban dictionary plugin for Hadouken.

=head1 AUTHOR

dek - L<http://dek.codes/>

=cut

