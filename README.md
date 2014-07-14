hadouken
====
Hadouken is a pluggable irc bot for fun and entertainment.


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



