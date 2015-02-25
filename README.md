<A name="toc1-4" title="Hadouken" />
# Hadouken

By Joe P <dek@dek.codes>


<A name="toc1-50" title="Status" />
#### Current Status ![Build Status](https://travis-ci.org/gitdek/hadouken.svg?branch=master)

<A name="toc2-9" title="Introduction" />
## Introduction
***

[Hadouken][] is an irc bot which aims to provide fun, information, and
channel management. The main goal is a simple plugin design so others can 
contribute even with limited time. There are many useful, and some not so
useful plugins included to begin with.

<A name="toc2-16" title="Getting Started" />
## Getting Started
***
This is straight forward and will take just a few minutes. I recommend using
perlbrew for a newer version of perl and to keep things seperated from the
system.

It's `perl Makefile.PL; make; sudo make install`.

Now modify your configuration. By default it is in /etc/hadouken.conf.
Once completed we're going to run `hadouken --setup` to encrypt the config
file on disk. This requires you to set a password, so don't forget it.

Now you are able to run hadouken with `hadouken start` to run it as a daemon.

If you would like to setup hadouken as a service you can generate the init file
by running `hadouken get_init_file > /etc/init.d/hadouken`.


<A name="toc2-103" title="Command-line options" />
## Command-line Options
***
Make sure you make a backup of your configuration. It's possibly you might
encrypt it twice by accident, rendering it useless.

*   Run service:

    > hadouken start

*   Stop service:
        
    > hadouken stop

*   Restart service:

    > hadouken restart

*   Get service status:

    > hadouken status

*   Specify another configuration:

    > hadouken --config=[file]

*   Run in foreground:
    
    > hadouken foreground

*   Encrypt configuration file:
	
	> hadouken --setup

*   Display encrypted configuration file:
	
	> hadouken --showconfig

*   Provide password as an argument:
	
	> hadouken --password=[passwd]
	
*   Generate init file for Hadouken
    
    > hadouken get_init_file
`

<A name="toc2-139" title="Core Commands" />
## Core Commands
***
These are the core commands of Hadouken. There are many plugin-ins as well so
make yourself familiar with those.

> ### Common command aliases
***
> 1. Command: `remove`.
> > Alias: `rm`, `rem`, `del`, `delete`.
>
> 2. Command: `list`.
> > Alias: `ls`.
>
> 3. Command: `all`.
> > Alias: `*`.


> ### Command Prefixes
***
> 1.   Prefix: `.`
> > eg .admin add dek@dek.org
>
> 2.   Prefix: `hadouken`
> > eg hadouken admin ls
>
> 3.   Prefix: `hadouken,`
> > eg hadouken, weather jfk
>

### Administrative commands
***
Commands for management of admin users:

* admin add [ident@host.com]
* admin rm [ident@host.com]
* admin ls
* admin grep [string]
* admin key [password] - Set a password used for admin communication or optionally perform a Diffie-Hellman key exchange.
* admin reload - Reload hadouken.

Commands for management of whitelisted users:

* whitelist add [ident@host.com]
* whitelist rm [ident@host.com]
* whitelist ls

Commands for management of blacklisted users:

* blacklist add [ident@host.com]
* blacklist rm [ident@host.com]
* blacklist ls

Commands for management of channels:

* channel add [#channel]
* channel rm [#channel]
* channel ls
* channel mode [#channel]
* channel mode [#channel] [modes]


#### Channel Modes:
***
`+O`    Automatically op admins when they join a channel.

`+W`    Automatically op whitelisted user when they join a channel.

`+P`    Protect admin users from de-op/kick/ban.

`+V`    Protect whitelisted users.

`+U`    Automatically shorten url displayed.

`+A`    Aggressive mode if protection is triggered.

`+Z`    Allow plugins to be used in the specified channel.

`+F`    Fast op mode. No verification of op mode changes.


#### Plugin commands
***
* plugin [arg] status - Get status of plugin or use wildcard for status of all available plugins.

* plugin [arg] load - Load plugin or use wildcard to load all available plugins.

* plugin [arg] unload - Unload plugin or use wildcard to unload all available plugins.

* plugin [arg] reload - Reload plugin or use wildcard to reload all available plugins.

* plugin [arg] autoload on - Set autoload on for plugin, or use wildcard for every available plugin.

* plugin [arg] autoload off - Set autoload off for plugin, or use wildcard for every available plugin.


#### Miscellaneous commands
***
* commands - Get a list of commands you are able to access determined by your ACL.
* plugins - Get a list of available plugins you can access determined by your ACL.
* raw - Send raw command to server. eg: .raw privmsg dek hello.
* stats - Get version info and uptime.
* powerup - If the bot is oped, it will op you.
* trivia start - Start trivia game.
* trivia stop - Stop trivia game.

- - -

<A name="toc2-159" title="Issues" />
## Issues
***
Hadouken has been tested on the following versions of perl:

*  perl-5.16.3
*  perl-5.19.0
*  perl-5.19.8
*  perl-5.20.1
*  perl-5.21.0
*  perl-5.21.6


These dependencies may not be satisfied, but this is very rare.

If you have issues with Math::Pari and Digest::MD2 follow the directions below. If you have issues with Digest::MD2 only, jump to step 10.

1. wget http://search.cpan.org/CPAN/authors/id/I/IL/ILYAZ/modules/Math-Pari-2.01080605.tar.gz
2. wget http://search.cpan.org/CPAN/authors/id/I/IL/ILYAZ/modules/pari/pari-2.1.7.tgz
3. tar -zxvf Math-Pari-2.01080605.tar.gz
4. tar -zxvf pari-2.1.7.tgz
5. cd Math-Pari-2.01080605
6. Edit Makefile.PL
7. Change $paridir = "../pari-2.1.7";
8. perl Makefile.PL machine=none
9. make install
10. apt-get install libdigest-md2-perl


[Hadouken]: http://github.com/gitdek/hadouken/
[Dekcodes]: http://dek.codes/

