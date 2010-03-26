package Redis::YA;
use strict;
use warnings;
use 5.00800;
our $VERSION = '0.01';
use IO::Socket::INET 1.31;
use Carp ();

# see redis.tcl
our $BULK_COMMAND = {
	SET   => 1,	SETNX => 1,
	RPUSH => 1,	LPUSH => 1,
	LSET  => 1,	LREM  => 1,
	SADD  => 1,	SREM  => 1,
    SISMEMBER => 1,
    ECHO      => 1,
    GETSET    => 1,
    SMOVE     => 1,
    ZADD      => 1,
    ZREM      => 1,
    ZSCORE    => 1,
    ZINCRBY   => 1,
    APPEND    => 1,
};

sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;
    my $self = bless {
        buf     => '',
        server  => '127.0.0.1:6379',
        %args
    }, $class;

    $self->{sock} ||= IO::Socket::INET->new(
        PeerAddr => $self->{server},
        Proto    => 'tcp',
    ) || die "Cannot open socket($self->{server}): $!";

    return $self;
}

# for AUTOLOAD
sub DESTROY {}

our $AUTOLOAD;
sub AUTOLOAD {
    my $self = shift;

    my $command = $AUTOLOAD;
    $command =~ s/.*://;
    $command = uc($command);
    no strict 'refs';
    *{$AUTOLOAD} = sub { shift->_send_command($command, @_) };
    $self->_send_command($command, @_);
}

sub _send_command {
    my ($self, $command, @args) = @_;
    my $sock = $self->{sock} || die "no server connected";
    local $self->{working_command} = $command;

    my $send = do {
        if ( defined $BULK_COMMAND->{$command} ) {
            my $value = pop @args;
               $value = '' if !defined $value;

            $command . ' ' . join( ' ', @args ) . ' ' . length($value) . "\r\n$value\r\n";
        }
        else {
            $command . ' ' . join( ' ', @args ) . "\r\n";
        }
    };
    print {$sock} $send;

    if ( $command eq 'QUIT' ) {
        close($sock) || die "can't close socket: $!";
        undef $self->{sock};
        return 1;
    }

    return $self->_read_reply();
}

sub _read_reply {
    my ($self, ) = @_;

    my $sock = $self->{sock};
    my $buf = <$sock>;
    my $type = substr($buf, 0, 1);
    $buf = substr($buf, 1, -2); # -2 means length("\015\012")

    # With an error message (the first byte of the reply will be "-")
    # With a single line reply (the first byte of the reply will be "+)
    # With bulk data (the first byte of the reply will be "$")
    # With multi-bulk data, a list of values (the first byte of the reply will be "*")
    # With an integer number (the first byte of the reply will be ":")
    if ( $type eq '-' ) {
        Carp::croak("[$self->{working_command}] $buf");    # error message
    }
    elsif ( $type eq '+' ) {                  # Single line reply
        return $buf;
    }
    elsif ( $type eq '$' ) {                  # bulk data
        if ( $self->{working_command} eq 'INFO' ) {
            my $hash;
            foreach my $l ( split( /\015\012/, $self->_read_bulk_reply($buf) ) ) {
                my ( $n, $v ) = split( /:/, $l, 2 );
                $hash->{$n} = $v;
            }
            return $hash;
        }
        elsif ( $self->{working_command} eq 'KEYS' ) {
            my $keys = $self->_read_bulk_reply($buf);
            return split(/\032/, $keys) if $keys; # \032 means SPACE
            return undef;
        } else {
            return $self->_read_bulk_reply($buf);
        }
    }
    elsif ( $type eq '*' ) {                  # multi-bulk reply
        return $self->_read_multi_bulk($buf);
    }
    elsif ( $type eq ':' ) {                  # integer number
        return 0+$buf;
    }
    else {
        Carp::confess( "unknown type: $type", $self->__read_line() );
    }
}

sub _read_bulk_reply {
    my ($self, $n) = @_;
    return undef if $n < 0;

    $self->{sock}->read(my $buf, $n+2) == $n+2
        or Carp::confess("[$self->{working_command}] cannot read bulk reply: $!");
    return substr($buf, 0, $n);
}

sub _read_multi_bulk {
    my ($self, $n) = @_;
    return undef if $n < 0;

    my @res;
    for my $i (0..$n-1) {
        push @res, $self->_read_reply($_);
    }
    return @res;
}

# debugging utility
sub _packit {
    local $_ = shift;
    $_ =~ s{([\r\n]|\p{IsCntrl})}{ '\x' . unpack("H*", $1) }ge;
    $_;
}


1;
__END__

=encoding utf8

=head1 NAME

Redis::YA -

=head1 SYNOPSIS

  use Redis::YA;

=head1 DESCRIPTION

Redis::YA is yet another redis client library.

=head1 Difference between L<Redis>

=over 4

=item Do not mention the utf8 flag

=item Do not use $ENV{REDIS_SERVER}

I dislike to load configuration from envrionment variables.

=back

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom AAJKLFJEF GMAIL COME<gt>

=head1 SEE ALSO

=head1 LICENSE

Copyright (C) Tokuhiro Matsuno

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
