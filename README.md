# Hadouken

# Dependencies:

The only problem i've come across so far is with Math::Pari


wget http://search.cpan.org/CPAN/authors/id/I/IL/ILYAZ/modules/Math-Pari-2.01080605.tar.gz
wget http://search.cpan.org/CPAN/authors/id/I/IL/ILYAZ/modules/pari/pari-2.1.7.tgz

tar -zxvf Math-Pari-2.01080605.tar.gz
tar -zxvf pari-2.1.7.tgz
cd Math-Pari-2.01080605

editor Makefile.PL
Change $paridir = "../pari-2.1.7";

perl Makefile.PL machine=none
make install
