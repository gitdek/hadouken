use strict;
use warnings;
#use ExtUtils::MakeMaker;
use inc::Module::Install;

WriteMakefile(
    NAME                => 'Hadouken',
    AUTHOR              => q{dek <dek@dek.bz>},
    VERSION_FROM        => 'lib/Hadouken.pm',
    ABSTRACT            => 'Hadouken',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    CONFIGURE_REQUIRES => { 
        'ExtUtils::MakeMaker'   => 0, 
        'YAML',                 => 0,
        'Test::More'            => 0,
        'File::Copy'            => 0 
    },
    PREREQ_PM => {
        'Cwd'                   => 0,
        'Moose'                 => 0,
        'List::MoreUtils'       => 0,
        'List::Util'            => 0,
        'AnyEvent'              => 0,
        'AnyEvent::IRC::Client' => 0,
        'AnyEvent::DNS'         => 0,
        'AnyEvent::IRC::Util'   => 0,
        'HTML::TokeParser'      => 0,
        'URI'                   => 0,
        'LWP::UserAgent'        => 0,
        'LWP::ConnCache'        => 0,
        'HTTP::Cookies'         => 0,
        'Encode'                => 0,
        'JSON::XS'              => 0,
        'POSIX'                 => 0,
        'Time::HiRes'           => 0,
        'Geo::IP'               => 0,
        'Yahoo::Weather'        => 0,
        'Tie::Array::CSV'       => 0,
        'Text::CSV_XS'          => 0,
        'Regexp::Common'        => 0,
        'String::IRC'           => 0,
        'Net::Whois::IP'        => 0,
        'Crypt::RSA'            => 0,
        'Convert::PEM'          => 0,
        'MIME::Base64'          => 0,
        'Crypt::OpenSSL::RSA'   => 0,
        'Crypt::Blowfish_PP'    => 0,
        'Time::Elapsed'         => 0,
        'TryCatch'              => 0,
        'Daemon::Control'       => 0,
        'Config::General'       => 0,
        'File::Basename'        => 0,
    },
	PM => {'lib/Hadouken.pm' => '$(INST_LIB)/Hadouken.pm'},
	# EXE_FILES => ['bin/hadouken'],
	PL_FILES => {'bin/createconfig.pl' => '/etc/hadouken.conf'},
    dist => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
);

auto_install();
