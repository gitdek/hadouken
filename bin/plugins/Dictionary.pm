package Hadouken::Plugin::Dictionary;

use strict;
use warnings;

use String::IRC;
use TryCatch;
use Encode qw( encode ); 
use JSON::XS qw( encode_json decode_json );
use Data::Dumper;

our $VERSION = '0.2';
our $AUTHOR = 'dek';


# Description of this command.
sub command_comment {
    my $self = shift;

    return "Dictionary lookup. command alias: define";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "dictionary";
}

sub command_regex {
    my $self = shift;

    return '(dictionary|define)\s.+?';
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

    return 
        unless 
            (defined($arg) && length($arg));


    my $origin_arg = $arg;
    $arg = 'awesome' if (lc($arg) =~ 'dek');
    $arg = 'penis' if (lc($arg) =~ 'luchini');
    $arg = 'elite' if (lc($arg) =~ 'marin');
    $arg = 'elite' if (lc($arg) =~ 'menace');

    my $define_url = "http://glosbe.com/gapi/translate?from=eng&dest=eng&format=json&phrase=".$arg."&pretty=true";

    $self->asyncsock->get($define_url, sub {
        my ($body, $header) = @_;
        my $json = $self->_jsonify($body);

        return
            unless 
                ((defined $json) && 
                (exists $json->{'tuc'}));
                #(exists $json->{'tuc'}->[0]->{meanings}); 

                
        my $arg_pretty = String::IRC->new($origin_arg)->bold; #$json->{phrase})->bold;
        my $meaning = $json->{tuc}->[0]->{meanings}->[0]->{text};
        #warn $meaning;

        return 
            unless
                ((defined $meaning) && (length($meaning)));

        my $ret =  "[$arg_pretty] Defintion: ".$meaning;
        $self->send_server (PRIVMSG => $channel, $ret);
    });

    return 1;
}

sub _jsonify {
    my $self = shift;
    my $arg = shift;
    my $hashref;
    try {
        $hashref = decode_json( encode("utf8", $arg) );
    } catch($e) {
        $hashref = undef;
    }
    return $hashref;
}




1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Hadouken::Plugin::Dictionary - Dictionary plugin.

=head1 DESCRIPTION

Dictionary plugin for Hadouken.

=head1 AUTHOR

dek - L<http://dek.codes/>

=cut

