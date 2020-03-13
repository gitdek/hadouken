package Hadouken::Plugin::Boobs;

use strict;
use warnings;

use Hadouken ':acl_modes';

use TryCatch;

our $VERSION = '0.1';
our $AUTHOR  = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return "Get a random synonym for boobs";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "boobs";
}

sub command_regex {

    return 'boobs$';
}

# Return 1 if OK.
# 0 if does not pass ACL.
sub acl_check {
    my ( $self, %aclentry ) = @_;

    my $permissions = $aclentry{'permissions'};
    my $who         = $aclentry{'who'};
    my $channel     = $aclentry{'channel'};
    my $message     = $aclentry{'message'};

    # Hadouken::BIT_ADMIN OR Hadouken::BIT_WHITELIST OR Hadouken::BIT_OP Hadouken::NOT_RIP
    #my $minimum_perms = (1 << 0) | (1 << 1) | (1 << 3);

    #my $acl_min = (1 << Hadouken::BIT_ADMIN) | (1 << Hadouken::BIT_WHITELIST) | (1 << Hadouken::NOT_RIP);

    #my $value = ($permissions & $minimum_perms);

    #warn $value;

    #if($value > 0) {
    # At least one of the items is set.
    #    return 1;
    #}

    # Or you can do it with the function Hadouken exports.
    # Make sure at least one of these flags is set.
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

    try {
        my $line;
        open( my $fh, '<' . $self->{Owner}->{ownerdir} . '/../data/hooters' ) or die $!;
        srand;
        rand($.) < 1 && ( $line = $_ ) while <$fh>;
        close($fh);

        $self->send_server( PRIVMSG => $channel, "[boobs] - " . lc($line) );

    }
    catch ($e) {
        warn $e;
    }

    return 1;
} ## ---------- end sub command_run

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Hadouken::Plugin::Boobs - Boobs plugin.

=head1 DESCRIPTION

A plugin for Hadouken which makes learning new words
fun. Specifically ones meaning boobs. 

=head1 AUTHOR

dek <dek@whilefalsedo.com>

=cut

