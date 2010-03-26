package Redis::Fast;
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
our $BUFSIZ = 1024;

sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{$_[0]} : @_;
    my $self = bless {
        buf     => '',
        timeout => 10,
        server  => '127.0.0.1:6379',
        %args
    }, $class;

    $self->{sock} ||= IO::Socket::INET->new(
        PeerAddr => $self->{server},
        Proto    => 'tcp',
    ) || die "Cannot open socket($self->{server}): $!";
    $self->{sock}->blocking(0);
    $self->{sock}->autoflush(1);

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
    $self->_write_all($send);

    if ( $command eq 'QUIT' ) {
        close($sock) || die "can't close socket: $!";
        undef $self->{sock};
        return 1;
    }

    return $self->_read_reply();
}

sub _write_all {
    my ($self, $buf) = @_;
    my $len = length($buf);
    my $offset = 0;
    my $win = '';
    vec($win, fileno($self->{sock}), 1) = 1;
    my $wout;
    do {
        my $done = $self->{sock}->syswrite( $buf, $len, $offset );
        $len -= $done;
        $offset += $done;

        if ($len > 0) {
            unless (select(undef, $wout=$win, undef, $self->{timeout})) {
                Carp::confess("[$self->{working_command}] Cannot write to socket by timeout: $self->{server}");
            }
        }
    } while ($len > 0);
}

sub _read_more {
    my $self = shift;

    my $done = sysread( $self->{sock}, $self->{buf}, $BUFSIZ, length($self->{buf}) );
    return $done if $done;

    my $rin = '';
    vec($rin, fileno($self->{sock}), 1) = 1;
    unless (select($rin, undef, undef, $self->{timeout})) {
        Carp::confess("[$self->{working_command}] Cannot read form socket: $self->{server}");
    }
    sysread( $self->{sock}, $self->{buf}, $BUFSIZ, length($self->{buf}) )
        or Carp::confess("[$self->{working_command}] Cannot read from socket: $self->{server}");
}

sub _read_reply {
    my ($self, ) = @_;

    my $type;
    while (1) {
        if ($self->{buf} =~ s/^(.)//) {
            $type = $1;
            last;
        } else {
            $self->_read_more();
        }
    }

    # With an error message (the first byte of the reply will be "-")
    # With a single line reply (the first byte of the reply will be "+)
    # With bulk data (the first byte of the reply will be "$")
    # With multi-bulk data, a list of values (the first byte of the reply will be "*")
    # With an integer number (the first byte of the reply will be ":")
    if ( $type eq '-' ) {
        Carp::croak("[$self->{working_command}] $self->{buf}");    # error message
    }
    elsif ( $type eq '+' ) {                  # Single line reply
        while (1) {
            if ($self->{buf} =~ s/^(.+?)\015\012//) {
                return $1;
            } else {
                $self->_read_more();
            }
        }
    }
    elsif ( $type eq '$' ) {                  # bulk data
        if ( $self->{working_command} eq 'INFO' ) {
            my $hash;
            foreach my $l ( split( /\015\012/, $self->_read_bulk_reply() ) ) {
                my ( $n, $v ) = split( /:/, $l, 2 );
                $hash->{$n} = $v;
            }
            return $hash;
        }
        elsif ( $self->{working_command} eq 'KEYS' ) {
            my $keys = $self->_read_bulk_reply();
            return split(/\032/, $keys) if $keys; # \032 means SPACE
            return undef;
        } else {
            return $self->_read_bulk_reply();
        }
    }
    elsif ( $type eq '*' ) {                  # multi-bulk reply
        return $self->_read_multi_bulk();
    }
    elsif ( $type eq ':' ) {                  # integer number
        while (1) {
            if ($self->{buf} =~ s/^(-?[0-9]+?)\015\012//) {
                return $1;
            } else {
                $self->_read_more();
            }
        }
    }
    else {
        Carp::confess( "unknown type: $type", $self->__read_line() );
    }
}

sub _read_bulk_reply {
    my ($self) = @_;

    my $n;
    while (1) {
        if ($self->{buf} =~ s/^(-?[0-9]+?)\015\012//) {
            $n = $1;
            last;
        } else {
            $self->_read_more();
        }
    }
    return undef if $n < 0;

    while (1) {
        if (length($self->{buf}) >= $n+2) {
            my $res = substr($self->{buf}, 0, $n);
            $self->{buf} = substr($self->{buf}, $n+2); # skip \r\n
            return $res;
        } else {
            $self->_read_more();
        }
    }
}

sub _read_multi_bulk {
    my ($self) = @_;

    my $n;
    while (1) {
        if ($self->{buf} =~ s/^(-?[0-9]+?)\015\012//) {
            $n = $1;
            last;
        } else {
            $self->_read_more();
        }
    }
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

Redis::Fast -

=head1 SYNOPSIS

  use Redis::Fast;

=head1 DESCRIPTION

Redis::Fast is

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom AAJKLFJEF GMAIL COME<gt>

=head1 SEE ALSO

=head1 LICENSE

Copyright (C) Tokuhiro Matsuno

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
