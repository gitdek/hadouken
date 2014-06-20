package Hadouken::Plugin::Translate;

use strict;
use warnings;

use String::IRC;
use TryCatch;
use Encode qw( encode ); 
use JSON::XS qw( encode_json decode_json );
use Data::Dumper;

our $VERSION = '0.1';
our $AUTHOR = 'dek';


my %iso3_codes = ('english' => 'eng', 'korean' => 'kor', 'italian' => 'ita', 'dutch' => 'nld', 'french' => 'fra','portuguese' => 'por', 'arabic' => 'ara','russian' => 'rus','spanish' => 'spa','german' => 'deu','japanese' => 'jpn');

# Description of this command.
sub command_comment {
    my $self = shift;

    return "Translate <language> <word> german french spanish etc";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "translate";
}

sub command_regex {
    my $self = shift;
    return 'translate\s.+?';
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

    my ($cmd, $arg) = split(/ /, lc($message), 2);

    return 
        unless 
            (defined($arg) && length($arg));


    my ($dstlang, $phrase) = split(/ /,$arg,2);

    chomp($dstlang);
    chomp($phrase);

    my $srclang = 'english';

    my $src_lang = 'eng';

    if($dstlang =~ m/\-/) {
        my ($src,$dst) = split(/-/,$dstlang,2);

        if(defined $src && length $src && exists $iso3_codes{$src}) {
            $srclang = $src;
            $src_lang = $iso3_codes{$src};
            $dstlang = $dst;
        }
    } else {
        if($dstlang ne 'english') {
            $srclang = 'english';
            #$dstlang = 'english';
        }
    }

    return 
        unless 
            (defined $dstlang && length $dstlang && defined $phrase && length $phrase);

    return 
        unless 
            exists $iso3_codes{$dstlang} && exists $iso3_codes{$srclang};


    warn "trying $srclang $dstlang $phrase";
    
    my $dest_lang = $iso3_codes{$dstlang};
    $src_lang = $iso3_codes{$srclang};

    my $encoded_phrase = $phrase;
    
    $encoded_phrase = 'penis' if $encoded_phrase =~ 'luchini';
    $encoded_phrase = 'awesome' if $encoded_phrase =~ 'dek';

    $encoded_phrase =~ s/ /\%20/g;

    #warn $encoded_phrase;

    my $define_url = "http://glosbe.com/gapi/translate?from=".$src_lang."&dest=".$dest_lang."&format=json&phrase=".$encoded_phrase."&pretty=true";

    $self->asyncsock->get($define_url, sub {
        my ($body, $header) = @_;
        my $json = $self->_jsonify($body);

        # print Dumper($json);

        return
            unless 
                ((defined $json) && 
                (exists $json->{'tuc'}));
                #(exists $json->{'tuc'}->[0]->{meanings}); 

                
        my $arg_pretty = String::IRC->new($phrase)->bold; #$json->{phrase})->bold;       
        my $translation = $json->{tuc}->[0]->{phrase}->{text};
        #warn $translation;

        return 
            unless
                ((defined $translation) && (length($translation)));

        my $ret =  "[$arg_pretty] $dstlang($dest_lang): ".$translation;
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

