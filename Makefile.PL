# use 5.008;
use strict;
use warnings;
use warnings FATAL => 'all';
use inc::Module::Install;

include     ('ExtUtils::AutoInstall');

my @exe_files;

if ($ENV{HADOUKEN_INSTALL_TOOLS}) {
   push @exe_files, 'bin/hadouken';
}

if (eval ($ExtUtils::MakeMaker::VERSION) <= 6.55) {
    print "\n[ERROR]: ExtUtils::MakeMaker >= 6.5503 is required to build the package correctly.\n";
    print "The installed version is $ExtUtils::MakeMaker::VERSION.\n";
    print "Install the latest ExtUtils::MakeMaker and try again. Exiting.\n";
    exit(1);
}

WriteMakefile(
    NAME                => 'Hadouken',
    AUTHOR              => q{dek <dek@dek.bz>},
    VERSION             => '0.9.0',
    ABSTRACT            => 'Hadouken chat bot',

    CONFIGURE_REQUIRES  => { 
        'ExtUtils::MakeMaker'   => 6.5503, 
        'YAML',                 => 0,
    },

    BUILD_REQUIRES => {
        'Test::More'            => 0,
        'File::Copy'            => 0
    },

    EXE_FILES => [ @exe_files ],

    PREREQ_PM           => {
        'experimental'          => 0,
        'Scalar::Util'          => 0,
        'Cwd'                   => 0,
        'Moose'                 => 0,
        'List::MoreUtils'       => 0,
        'List::Util'            => 0,
        'AnyEvent'              => 0,
        'AnyEvent::DNS'         => 0,
        'AnyEvent::Whois::Raw'  => 0,
        'HTML::TokeParser'      => 0,
        'HTML::Strip'           => 0,
        'URI'                   => 0,
        'URI::Escape'           => 0,
        'LWP::UserAgent'        => 0,
        'LWP::ConnCache'        => 0,
        'HTTP::Cookies'         => 0,
        'Encode'                => 0,
        'JSON::XS'              => 0,
        'JSON'                  => 0,
        'POSIX'                 => 0,
        'Time::HiRes'           => 0,
        'Geo::IP'               => 0,
        'Yahoo::Weather'        => 0,
        'Tie::Array::CSV'       => 0,
        'Text::CSV_XS'          => 0,
        'Regexp::Common'        => 0,
        'Regexp::Assemble'      => 0,
        'String::IRC'           => 0,
        'Net::Whois::IP'        => 0,
        'Convert::PEM'          => 0,
        'MIME::Base64'          => 0,
        'Time::Elapsed'         => 0,
        'TryCatch'              => 0,
        'Daemon::Control'       => 0,
        'Config::General'       => 0,
        'File::Basename'        => 0,
        'Crypt::RSA'            => 0,
        'Crypt::OpenSSL::RSA'   => 0,
        'Crypt::Blowfish_PP'    => 0,
        'Crypt::Random'         => 0,
        'Crypt::CBC'            => 0,
        'File::Spec'            => 0,
        'FindBin'               => 0,
        'Module::Pluggable'     => 0,
        'Data::Printer'			=> 0,
        'Data::Dumper'          => 0,
        'Any::Moose'            => 0,
        'MooseX::Getopt::GLD'   => 0,
        'Object::Event'         => 0,
        'Digest::SHA3'          => 0,
        'Digest::SHA'           => 0,
        'Term::ReadPassword'    => 0,
        'Text::Unidecode'       => 0,
        'REST::Google'          => 0,
        'Log::Log4perl'         => 0,
        'IMDB::Film'            => 0,
        'AnyEvent::SlackRTM'    => 0,
        'Try::Tiny'             => 0,
        'Redis'                 => 0,
        'Net::ZooKeeper'        => 0,
        'CHI'                   => 0,
        'Math::BigInt'          => 0
    },

   (( eval { ExtUtils::MakeMaker->VERSION(6.46) } ) ?
      ( META_MERGE => {
         'build_requires' => {
            'ExtUtils::MakeMaker' => 0,
            'Test::More'          => 0.45
         },
         'no_index' => {
            'file' => [
               'bin/hadouken'
            ]
         },
         'resources' => {
            'homepage'   => 'https://github.com/gitdek/hadouken',
            'repository' => 'https://github.com/gitdek/hadouken',
            'license'    => 'http://dev.perl.org/licenses/'
         },
         'provides' => {
            'Hadouken' => {
               'file'    => 'lib/Hadouken.pm',
               'version' => '0.9.0'
            },
            'Hadouken::AsyncSocket' => {
               'file'    => 'lib/Hadouken/AsyncSocket.pm',
               'version' => '0.2'
            },
            'Hadouken::DH1080' => {
               'file'    => 'lib/Hadouken/DH1080.pm',
               'version' => '0.1'
            },
         }
      } ) : () ),

    (( eval { ExtUtils::MakeMaker->VERSION(6.31) } ) ?
      ( LICENSE => 'perl' ) : () ),

   (( eval { ExtUtils::MakeMaker->VERSION(6.48) } ) ?
      ( MIN_PERL_VERSION => 5.008 ) : () ),

   ((!eval { ExtUtils::MakeMaker->VERSION(6.25) } ) ?
      ( PL_FILES => { 
                #'bin/createconfig.pl' => '/etc/hadouken.conf',
                'bin/deflategeoip.pl' => 'skip', #'skip',
        } ) : () ),

    # PM => { # We don't want to install ALL plugins by default.
    #     'lib/Hadouken.pm' => '$(INST_LIB)/Hadouken.pm',
    #     'lib/AsyncSocket.pm' => '$(INST_LIB)/AsyncSocket.pm',
    #     'lib/Hadouken/DH1080.pm' => '$(INST_LIB)/Hadouken/DH1080.pm',
    #     'bin/plugins/StockMarket.pm' => '$(INST_LIB)/Hadouken/Plugin/StockMarket.pm',
    #     'bin/plugins/IMDB.pm' => '$(INST_LIB)/Hadouken/Plugin/IMDB.pm',
    #     'bin/plugins/Weather.pm' => '$(INST_LIB)/Hadouken/Plugin/Weather.pm',
    #     'bin/plugins/Dictionary.pm' => '$(INST_LIB)/Hadouken/Plugin/Dictionary.pm',
    #     'bin/plugins/Shorten.pm' => '$(INST_LIB)/Hadouken/Plugin/Shorten.pm',
    #     'bin/plugins/MitchQuotes.pm' => '$(INST_LIB)/Hadouken/Plugin/MitchQuotes.pm',
    # },
    PMLIBDIRS => ['lib','bin/plugins'],

    dist => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },

    INSTALLDIRS => ( ($] < 5.011) ? 'perl' : 'site' )
);

#auto_install(
#    make_args   => '--hello',   # option(s) for CPAN::Config
#    force       => 1,           # pseudo-option to force install
    #do_once     => 0,           # skip previously failed modules
#);

#WriteMakefile;

# WriteAll();

    auto_install();
    #&WriteAll;