package Hadouken::QuotedPrint;

use strict;
use vars qw(@ISA @EXPORT $VERSION);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(encode_qp decode_qp);

$VERSION = "0.2";

use Hadouken::Base64;  # will load XS version of {en,de}code_qp()

*encode = \&encode_qp;
*decode = \&decode_qp;

1;

__END__
