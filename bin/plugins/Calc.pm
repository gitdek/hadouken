package Hadouken::Plugin::Calc;

use strict;
use warnings;

use TryCatch;
use Data::Dumper;
use HTML::TokeParser;
use URI;

our $VERSION = '0.2';
our $AUTHOR = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return "Calculator. eg calc (G * mass of earth) / (radius of earth ^ 2)";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "calc";
}

sub command_regex {
    my $self = shift;

    return 'calc\s.+?';
}

# Return 1 if OK.
# 0 if does not pass ACL.
sub acl_check {
    my ($self, %aclentry) = @_;

    my $permissions = $aclentry{'permissions'};

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

    my ($cmd, $arg) = split(/ /, $message, 2); # DO NOT LC THE MESSAGE!

    return unless defined $arg;

    my $res_calc = $self->calc($arg);

    return unless defined $res_calc;

    $self->send_server (PRIVMSG => $channel, "[calc] $res_calc");

    return 1;

}
sub calc {
    my ($self, $expression) = @_;

    my $url = URI->new('http://www.google.com/search');
    $url->query_form(q => $expression);
    
    my $ret = undef;

    my $result = $self->{Owner}->_webclient->get($url);
    
    $ret = $self->parse_calc_result($result->content);
    $ret =~ s/[^[:ascii:]]+//g; # if $ret;

    #$self->asyncsock->get($url, sub {
    #        my ($body, $header) = @_;
    #        $ret = $self->parse_calc_result($body);
    #        $ret =~ s/[^[:ascii:]]+//g if $ret;
    #    });

    return $ret;
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



1;

