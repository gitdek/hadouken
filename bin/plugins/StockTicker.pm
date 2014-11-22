# Use StockMarket.pm plugin this one is obsolete.

package Hadouken::Plugin::StockTicker;
use strict;
use warnings;

use Finance::Quote;
use TryCatch;
use String::IRC;

our $VERSION = '0.2';
our $AUTHOR = 'dek';

# Description of this command.
sub command_comment {
    my $self = shift;

    return "Look up stock by stock <symbol(s)>";
}

# Clean name of command.
sub command_name {
    my $self = shift;

    return "stockticker";
}

sub command_regex {
    my $self = shift;

    return '(stock|\.)\s.+?';
}

# Return 1 if OK.
# 0 if does not pass ACL.
# command_run will only be called if ACL passes.
sub acl_check {
    my ($self, %aclentry) = @_;

    my $permissions = $aclentry{'permissions'};
    my $who = $aclentry{'who'};
    my $channel = $aclentry{'channel'};
    my $message = $aclentry{'message'};

    # Available acl flags:
    # Hadouken::BIT_ADMIN
    # Hadouken::BIT_WHITELIST
    # Hadouken::BIT_OP 
    # Hadouken::VOICE
    # Hadouken::BIT_BLACKLIST
    
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

    return 
    unless 
    (defined($arg) && length($arg));
    
    try {
        my $q = Finance::Quote->new();
        $q->require_labels(qw/price date high low volume/);
        $q->failover(0);
        $q->timeout(10);

        my @z = split(/ /,uc($arg));
        foreach my $sym(@z) {
            next unless (defined($sym) && length($sym));

            my %data = $q->fetch('usa', $sym);

            if ($data{$sym, 'success'}) {
                my $summary = $sym." "."(".$data{$sym,'name'}.") ";
                my $net_change = $data{$sym,'net'};
                my $p_change = $data{$sym,'p_change'};
                my $day_range = $data{$sym,'day_range'};
                my $year_range = $data{$sym,'year_range'};

                # Make everything pretty.
                my $pretty_nchange = String::IRC->new($net_change);
                my $pretty_pchange = String::IRC->new($p_change."%");
                $pretty_nchange->light_green if($net_change =~ /^\+/);
                $pretty_nchange->red if($net_change =~ /^\-/);
                $pretty_pchange->light_green if($p_change =~ /^\+/);
                $pretty_pchange->red if($p_change =~ /^\-/);
                $day_range =~ s/\s+//g;
                $year_range =~ s/\s+//g;

                $summary .= "Last: ".$data{$sym,'last'}." ".$pretty_nchange." ".$pretty_pchange." (Vol: ".$data{$sym,'volume'}.") ";
                $summary .= "Daily Range: (".$day_range.") Yearly Range: (".$year_range.") ";
                $self->send_server (PRIVMSG => $channel, $summary);
            } else {
                warn "Failure";
            }
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

Hadouken::Plugin::StockTicker - Stock ticker plugin.

=head1 DESCRIPTION

Stock ticker plugin for Hadouken.

=head1 AUTHOR

dek - L<http://dek.codes/>

=cut

