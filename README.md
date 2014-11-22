hadouken
====
Hadouken is a pluggable irc bot for fun, entertainment, and channel management.


Author
----
dek

iamevil@gmail.com

Requirements
----
1. Linux

2. Perl

Compiling and installing
----
1. Run perl Makefile.PL

2. Run make

3. Run make install

4. Optionally run bin/hadouken get_init_file > /etc/init.d/hadouken

5. Modify configuration, run hadouken --setup to encrypt the configuration file, then you can run hadouken.

Command-line options
----
    Run service:
        hadouken start

    Stop service:
        hadouken stop

    Restart service:
        hadouken restart

    Get service status:
        hadouken status

    Specify another configuration:
        hadouken --config=[file]

    Run in foreground:
        hadouken foreground

	Encrypt configuration file:
		hadouken --setup
	
    Display encrypted configuration file:
		hadouken --showconfig
		
Commands
----
    command aliases for 'remove' are: 'rm','rem','del','delete'.
    command aliases for 'list' are: 'ls'.
    command aliases for 'all' are: '*'.

<<<<<<< HEAD
command prefixes: '.', 'hadouken','hadouken,'.
eg: .admin add dek@dek.com
eg: hadouken, admin add dek@dek.com


admin add [ident@host.com]
admin rm [ident@host.com]
admin ls
admin grep [string]
admin key [password] - Set a blowfish key. We use blowfish for all communication of admin commands.
admin reload - Reload hadouken.

whitelist add [ident@host.com]
whitelist rm [ident@host.com]
whitelist ls

blacklist add [ident@host.com]
blacklist rm [ident@host.com]
blacklist ls

channel add [#channel]
channel rm [#channel]
channel ls
channel mode [#channel]
channel mode [#channel] [modes]

Channel Modes:
 +O  - auto op_admins
 +W  - auto op whitelist
 +P  - protect admins
 +V  - protect whitelist
 +U  - automatically shorten urls
 +A  - aggressive mode (kick/ban instead of -o, etc)
 +Z  - allow plugins to be used in this channel
 +F  - fast op (no cookies)


for plugins each command accepts a plugin name(case sensitive) or a wildcard for every available plugin.

plugin [PluginName] status - Get status of plugin or use wildcard for status of all available plugins.
plugin [PluginName] load - Load plugin or use wildcard to load all available plugins.
plugin [PluginName] unload - Unload plugin or use wildcard to unload all available plugins.
plugin [PluginName] reload - Reload plugin or use wildcard to reload all available plugins.
plugin [PluginName] autoload on - Set autoload on for plugin, or use wildcard for every available plugin.
plugin [PluginName] autoload off - Set autoload off for plugin, or use wildcard for every available plugin.

commands - Get a list of commands you are able to access determined by your ACL.
plugins - Get a list of available plugins you can access determined by your ACL.
raw - Send raw command to server. eg: .raw privmsg dek hello.
stats - Get version info and uptime.
powerup - Get opped in channel if you aren't already.
trivia start - Start trivia in the channel this command is ran in.
trivia stop - Stop trivia in the channel this command is ran in.

=======
    command prefixes: '.', 'hadouken','hadouken,'.
    eg: .admin add dek@dek.com
    eg: hadouken, admin add dek@dek.com
    
    
    admin add [ident@host.com]
    admin rm [ident@host.com]
    admin ls
    admin grep [string]
    admin key [password] - Set a blowfish key. We use blowfish for all communication of admin commands.
    admin reload - Reload hadouken.
    
    whitelist add [ident@host.com]
    whitelist rm [ident@host.com]
    whitelist ls
    
    blacklist add [ident@host.com]
    blacklist rm [ident@host.com]
    blacklist ls
    
    channel add [#channel]
    channel rm [#channel]
    channel ls
    channel mode [#channel]
    channel mode [#channel] [modes]
    
    Channel Modes:
     +O  - auto op_admins
     +W  - auto op whitelist
     +P  - protect admins
     +V  - protect whitelist
     +U  - automatically shorten urls
     +A  - aggressive mode (kick/ban instead of -o, etc)
     +Z  - allow plugins to be used in this channel
     +F  - fast op (no cookies)
    
    
    for plugins each command accepts a plugin name(case sensitive) or a wildcard for every available plugin.
    
    plugin [PluginName] status - Get status of plugin or use wildcard for status of all available plugins.
    plugin [PluginName] load - Load plugin or use wildcard to load all available plugins.
    plugin [PluginName] unload - Unload plugin or use wildcard to unload all available plugins.
    plugin [PluginName] reload - Reload plugin or use wildcard to reload all available plugins.
    plugin [PluginName] autoload on - Set autoload on for plugin, or use wildcard for every available plugin.
    plugin [PluginName] autoload off - Set autoload off for plugin, or use wildcard for every available plugin.
    
    commands - Get a list of commands you are able to access determined by your ACL.
    plugins - Get a list of available plugins you can access determined by your ACL.
    raw - Send raw command to server. eg: .raw privmsg dek hello.
    stats - Get version info and uptime.
    powerup - Get opped in channel if you aren't already.
    trivia start - Start trivia in the channel this command is ran in.
    trivia stop - Stop trivia in the channel this command is ran in.
    
>>>>>>> dc0277c2c96621aae6aa798a5c5f80bd29eaef23

Issues
----
Some dependencies may not be satisfied. 

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
