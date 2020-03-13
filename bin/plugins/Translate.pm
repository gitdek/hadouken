package Hadouken::Plugin::Translate;

use strict;
use warnings;
use utf8;

use Hadouken ':acl_modes';

use Text::Unidecode;

# use Data::Printer alias => 'Dumper', colored => 1;
use String::IRC;
use TryCatch;
use Encode qw( encode );
use JSON::XS qw( encode_json decode_json );

our $VERSION = '0.2';
our $AUTHOR  = 'dek';

my %iso2_codes = (
    'afrikaans'          => 'af',
    'albanian'           => 'sq',
    'arabic'             => 'ar',
    'azerbaijani'        => 'az',
    'basque'             => 'eu',
    'bengali'            => 'bn',
    'belarusian'         => 'be',
    'bulgarian'          => 'bg',
    'catalan'            => 'ca',
    'chinese'            => 'zh-cn',
    'chinesetraditional' => 'zh-tw',
    'croatian'           => 'hr',
    'czech'              => 'cs',
    'danish'             => 'da',
    'dutch'              => 'nl',
    'english'            => 'en',
    'esperanto'          => 'eo',
    'estonian'           => 'et',
    'filipino'           => 'tl',
    'finnish'            => 'fi',
    'french'             => 'fr',
    'galician'           => 'gl',
    'georgian'           => 'ka',
    'german'             => 'de',
    'greek'              => 'el',
    'gujarati'           => 'gu',
    'haitian creole'     => 'ht',
    'hebrew'             => 'iw',
    'hindi'              => 'hi',
    'hungarian'          => 'hu',
    'icelandic'          => 'is',
    'indonesian'         => 'id',
    'irish'              => 'ga',
    'italian'            => 'it',
    'japanese'           => 'ja',
    'kannada'            => 'kn',
    'korean'             => 'ko',
    'latin'              => 'la',
    'latvian'            => 'lv',
    'lithuanian'         => 'lt',
    'macedonian'         => 'mk',
    'malay'              => 'ms',
    'maltese'            => 'mt',
    'norwegian'          => 'no',
    'persian'            => 'fa',
    'polish'             => 'pl',
    'portuguese'         => 'pt',
    'romanian'           => 'ro',
    'russian'            => 'ru',
    'serbian'            => 'sr',
    'slovak'             => 'sk',
    'slovenian'          => 'sl',
    'spanish'            => 'es',
    'swahili'            => 'sw',
    'swedish'            => 'sv',
    'tamil'              => 'ta',
    'telugu'             => 'te',
    'thai'               => 'th',
    'turkish'            => 'tr',
    'ukrainian'          => 'uk',
    'urdu'               => 'ur',
    'vietnamese'         => 'vi',
    'welsh'              => 'cy',
    'yiddish'            => 'yi'
);

#my %iso2_codes = ('english' => 'en', 'korean' => 'ko', 'italian' => 'it', 'dutch' => 'nl', 'french' => 'fr','polish' => 'pl', 'portuguese' => 'po','russian' => 'ru','spanish' => 'es','swedish' => 'sv', 'german' => 'de','japanese' => 'ja');

my %iso3_codes = (
    'english'    => 'eng',
    'korean'     => 'kor',
    'italian'    => 'ita',
    'dutch'      => 'nld',
    'french'     => 'fra',
    'portuguese' => 'por',
    'arabic'     => 'ara',
    'russian'    => 'rus',
    'spanish'    => 'spa',
    'german'     => 'deu',
    'japanese'   => 'jpn',
    'swedish'    => 'swe'
);

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
    my ( $self, %aclentry ) = @_;

    my $permissions = $aclentry{'permissions'};

    if (   $self->check_acl_bit( $permissions, Hadouken::BIT_ADMIN )
        || $self->check_acl_bit( $permissions, Hadouken::BIT_WHITELIST )
        || $self->check_acl_bit( $permissions, Hadouken::BIT_OP ) )
    {

        return 1;
    }

    return 0;
} ## ---------- end sub acl_check

# Return 1 if OK (and then callback can be called)
# Return 0 and the callback will not be called.
sub command_run {
    my ( $self, $nick, $host, $message, $channel, $is_admin, $is_whitelisted ) = @_;

    my ( $cmd, $arg ) = split( / /, lc($message), 2 );

    return
        unless ( defined($arg) && length($arg) );

    my ( $dstlang, $phrase ) = split( / /, $arg, 2 );

    chomp($dstlang);
    chomp($phrase);

    my $srclang = 'english';

    my $src_lang = 'en';

    if ( $dstlang =~ m/\-/ ) {
        my ( $src, $dst ) = split( /-/, $dstlang, 2 );

        if ( defined $src && length $src && exists $iso2_codes{$src} ) {
            $srclang  = $src;
            $src_lang = $iso2_codes{$src};
            $dstlang  = $dst;
        }
    }
    else {
        if ( $dstlang ne 'english' ) {
            $srclang = 'english';
        }
    }

    return
        unless ( defined $dstlang
        && length $dstlang
        && defined $phrase
        && length $phrase );

    return
        unless exists $iso2_codes{$dstlang} && exists $iso2_codes{$srclang};

    # warn "trying $srclang $dstlang $phrase";

    my $dest_lang = $iso2_codes{$dstlang};
    $src_lang = $iso2_codes{$srclang};

    my $encoded_phrase = $phrase;

    # $encoded_phrase = 'penis' if $encoded_phrase =~ 'luchini';
    # $encoded_phrase = 'awesome' if $encoded_phrase =~ 'dek';

    $encoded_phrase =~ s/ /\%20/g;

    my $langpair = $src_lang . "|" . $dest_lang;

    #warn $encoded_phrase;

    my $define_url =
          "http://mymemory.translated.net/api/get?q="
        . $encoded_phrase
        . "&langpair="
        . $langpair;

    #my $define_url = "http://glosbe.com/gapi/translate?from=".$src_lang."&dest=".$dest_lang."&format=json&phrase=".$encoded_phrase."&pretty=true";

    $self->asyncsock->get(
        $define_url,
        sub {
            my ( $body, $header ) = @_;
            my $json = $self->_jsonify($body);

            # print Dumper($json);
            return
                unless ( ( defined $json )
                && ( exists $json->{'responseData'} ) );

            #(exists $json->{'tuc'}->[0]->{meanings});

            my $arg_pretty  = String::IRC->new($phrase)->bold;          #$json->{phrase})->bold;
            my $translation = $json->{responseData}->{translatedText};

            # $translation =~ s/[^[:ascii:]]+//g;
            $translation =~ s/([^[:ascii:]]+)/unidecode($1)/ge;

            #my $translation = $json->{tuc}->[0]->{phrase}->{text};
            # warn $translation;

            return
                unless ( ( defined $translation )
                && ( length($translation) ) );

            my $ret = "[$arg_pretty] $dstlang($dest_lang): " . $translation;
            $self->send_server( PRIVMSG => $channel, $ret );
        }
    );

    return 1;
} ## ---------- end sub command_run

sub _jsonify {
    my $self = shift;
    my $arg  = shift;
    my $hashref;
    try {
        $hashref = decode_json( encode( "utf8", $arg ) );
    }
    catch ($e) {
        $hashref = undef;
    }
    return $hashref;
} ## ---------- end sub _jsonify

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Hadouken::Plugin::Translate - Translate word or phrase.

=head1 DESCRIPTION

Translation plugin for Hadouken.

=head1 AUTHOR

dek <dek@whilefalsedo.com>

=cut

