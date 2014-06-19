package Hadouken::Plugin::UrbanDictionary;

use strict;
use warnings;

use String::IRC;
use URI::Escape;
use HTML::TokeParser;

#use Data::Printer alias => 'Dumper', colored => 1;

use TryCatch;

our $VERSION = '0.1';
our $AUTHOR = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return "urban dictionary lookup";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "urban";
}

sub command_regex {
    my $self = shift;

    return 'urban\s.+?';
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

    return 
        unless 
            (defined($arg) && length($arg));

    my $urban_url = 'http://www.urbandictionary.com/define.php?term='. uri_escape($arg);

    $self->asyncsock->get($urban_url, sub {
        my ($body, $header) = @_;

        return unless defined $body && defined $header;
        
        my $parser = HTML::TokeParser->new( \$body );
        
        while (my $token = $parser->get_tag('div')) {
            next unless (defined $token->[1] && exists $token->[1]{'class'});

            my $c = $token->[1]{'class'};

            if($c =~ 'meaning') {
                my $text = $parser->get_trimmed_text("/div");
            
                my $arg_pretty = String::IRC->new($arg)->bold;
                
                my $ret = "[$arg_pretty] - $text";

                $self->send_server (PRIVMSG => $channel, $ret);

                last;
            }

        }
    });

    return 1;
}



1;

