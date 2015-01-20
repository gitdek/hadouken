package Hadouken::Plugin::MitchQuotes;

use strict;
use warnings;

use Hadouken ':acl_modes';
use TryCatch;

our $VERSION = '0.2';
our $AUTHOR = 'dek';

our @visuals = ('default','cower','moose','duck','head-in','cock');

# Description of this command.
sub command_comment {
    my $self = shift;

    return "Random Mitch Hedberg quote";
}

# Clean name of command.
sub command_name {
    return "mitch";
}

sub command_regex {
    return 'mitch$';
}

# Return 1 if OK.
# 0 if does not pass ACL.
sub acl_check {
    my ($self, %aclentry) = @_;

    my $permissions = $aclentry{'permissions'};
    my $who = $aclentry{'who'};
    my $channel = $aclentry{'channel'};
    my $message = $aclentry{'message'};

    # Hadouken::BIT_ADMIN OR Hadouken::BIT_WHITELIST OR Hadouken::BIT_OP Hadouken::NOT_RIP
    #my $minimum_perms = (1 << 0) | (1 << 1) | (1 << 3);

    #my $acl_min = (1 << Hadouken::BIT_ADMIN) | (1 << Hadouken::BIT_WHITELIST) | (1 << Hadouken::NOT_RIP);

    #my $value = ($permissions & $minimum_perms);

    #warn $value;

    # Or you can do it with the function Hadouken exports.
    # Make sure at least one of these flags is set.
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
    my ($cmd, $arg) = split(/ /, lc($message),2);

    try {
        my $line;
        open(FILE,'<'.$self->{Owner}->{ownerdir}.'/../data/mitch_quotes') or die $!;
        srand;
        rand($.) < 1 && ($line = $_) while <FILE>;
        close(FILE);    

        # I disabled the below feature, it would use cowthink/cowsay plus @visuals arg to do funny ascii stuff.



        # Max of 4 lines(90width) or it looks odd.
        #
        #if(length($line) <= 360) {
        
        #   $line .= "\n";

        #   $line =~ s/\"/\'/g;
        ##   #$line =~ s/@/\@/g;
    
        #  my $visual_opts = scalar @visuals;
        #   my $rand_idx = int(rand($visual_opts));
        #   my $visual = $visuals[$rand_idx];

        #   my $binfile = int(rand(2)) % 2 ? "cowthink" : "cowsay";
        #   my $cow = qx(/usr/games/$binfile -f $visual -W 90 "$line");
            
        #   my @c = split(/\n/,$cow);

        #   foreach my $crap (@c) {
        #       $self->send_server(PRIVMSG => $channel, "$crap");
        #   }
            
        #   return 1;
        #}

        my $wrapped;
        ($wrapped = $line) =~ s/(.{0,300}(?:\s|$))/$1\n/g;
        
        warn $wrapped;

        my @lines = split(/\n/,$wrapped);

        my $cnt = 0;
        foreach my $l (@lines) {
            next unless defined $l && length $l;
            $cnt++;
            $self->send_server(PRIVMSG => $channel, $cnt > 1 ? $l : "Mitch Hedberg - $l");
        }
    }
    catch($e) {
        warn $e;
    }


    return 1;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Hadouken::Plugin::MitchQuotes - Mitch Hedberg quotes.

=head1 DESCRIPTION

Mitch Hedberg plugin for Hadouken.

=head1 AUTHOR

dek - L<http://dek.codes/>

=cut

