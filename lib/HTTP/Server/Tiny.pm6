use v6;
unit class HTTP::Server::Tiny;

use HTTP::Parser; # parse-http-request
use File::Temp;
use IO::Blob;

my class TempFile {
    has $.filename;
    has $.fh;

    method new() {
        self.bless()!initialize
    }

    my sub nonce () { return (".{$*PID}." ~ flat('a'..'z', 'A'..'Z', 0..9, '_').roll(10).join) }

    method !initialize() {
        # XXX insecure
        loop {
            $.filename = $*TMPDIR.child("p6-httpd" ~ nonce());
            last unless $.filename.e;
        }
        $.fh = open $.filename, :rw;
        self;
    }

    method write(Blob $b) {
        $.fh.write: $b
    }

    method read(Int(Cool:D) $bytes) {
        $.fh.read: $bytes
    }

    method seek(Int:D $offset, Int:D $whence) {
        $.fh.seek: $offset, $whence
    }

    method slurp-rest(:$bin!) {
        $.fh.slurp-rest: bin => $bin
    }

    method close() {
        try unlink $.filename;
        try close $.fh;
    }

    method DESTROY {
        self.close
    }
}

has $.port = 80;
has $.host = '127.0.0.1';
# XXX how do i get String replesentation of package name in right way?
has Str $.server-software = $?PACKAGE.perl;

sub info($message) {
    say "[INFO] [{$*THREAD.id}] $message";
}

my constant DEBUGGING = %*ENV<HST_DEBUG>.Bool;

my sub debug($message) {
    say "[DEBUG] [{$*PID}] [{$*THREAD.id}] $message" if DEBUGGING;
}

my multi sub error(Exception $err) {
    say "[{$*THREAD.id}] [ERROR] $err {$err.backtrace.full}";
}

my multi sub error(Str $err) {
    say "[{$*THREAD.id}] [ERROR] $err";
}

method new(Str $host, int $port) {
    self.bless(host => $host, port => $port);
}

method !create-temp-buffer($len) {
    if !$len.defined || $len < 64_000 {
        IO::Blob.new
    } else {
        TempFile.new;
    }
}


method run(HTTP::Server::Tiny:D: Sub $app) {
    # moarvm doesn't handle SIGPIPE correctly. Without this,
    # perl6 exit without any message.
    # -- tokuhirom@20151003
    signal(SIGPIPE).tap({ debug("Got SIGPIPE") });

    # TODO: I want to use IO::Socket::Async#port method to use port 0.
    say "http server is ready: http://$.host:$.port/";

    react {
        whenever IO::Socket::Async.listen($.host, $.port) -> $conn {
            LEAVE { try $conn.close }
            self!handler($conn, $app);
        }
    }
}

method !handler(IO::Socket::Async $conn, Sub $app) {
    debug("new request");
    my Buf $buf .= new;
    my $header-parsed = False;

    my Hash $env;
    LEAVE { try $env<psgi.input>.close }
    my $got-content-len = 0;

    CATCH {
        when /^"broken pipe"$/ {
            error("broken pipe");
            return;
        }
        default {
            error($_);
            return;
        }
    }

    my $read-chan = $conn.bytes-supply.Channel;

    # read headers
    loop {
        $buf ~= $read-chan.receive;

        (my $header_len, $env) = parse-http-request($buf);
        debug("http parsing status: $header_len");
        if $header_len > 0 {
            $buf = $buf.subbuf($header_len);
            last;
        } elsif $header_len == -1 { # incomplete header
            next;
        } elsif $header_len == -2 { # invalid request
            await $conn.print("400 Bad Request\r\n\r\nBad request");
            $conn.close;
            return;
        } else {
            die "should not reach here";
        }
    }

    my $content-length = $env<CONTENT_LENGTH>;
    if $content-length.defined {
        $content-length .= Int;
    }

    $env<psgi.input> //= self!create-temp-buffer($content-length);

    debug "content-length: $content-length";

    if $content-length.defined {
        my $cl = $content-length;
        while $cl > 0 {
            if $buf.elems > 0 {
                debug "got {$buf.elems} bytes";
                my $write-bytes = $buf.elems min $cl;
                $env<psgi.input>.write($buf.subbuf(0, $write-bytes)); # XXX blocking
                $cl -= $write-bytes;
                debug "remains $cl";
                last unless $cl > 0;
            }

            $buf ~= $read-chan.receive;
        }
    } else {
        # TODO: chunked request support
    }

    $env<psgi.input>.seek(0,0); # rewind

    debug 'run app';
    my ($status, $headers, $body) = sub {
        CATCH {
            error($_);
            return 500, [], ['Internal Server Error!'.encode('utf-8')];
        };
        return $app.($env);
    }.();

    debug 'sending response';
    self!send-response($conn, $status, $headers, $body);

    debug 'closing';
}

method !send-response($csock, $status, $headers, $body) {
    debug "sending response";

    my $resp_string = "HTTP/1.0 $status perl6\r\n";
    my %send_headers;
    for @($headers) {
        if .key ~~ /<[\r\n]>/ {
            die "header split";
        }
        $resp_string ~= "{.key}: {.value}\r\n";

        my $lck = .key.lc;
        %send_headers{$lck} = .value;
    }
    unless %send_headers<server> {
        $resp_string ~= "server: $.server-software\r\n";
    }
    $resp_string ~= "\r\n";

    my $resp = $resp_string.encode('ascii');
    await $csock.write($resp);

    debug "sent header";

    if $body ~~ Array {
        for @($body) -> $elem {
            if $elem ~~ Blob {
                await $csock.write($elem);
            } else {
                die "response must be Array[Blob]. But {$elem.perl}";
            }
        }
    } elsif $body ~~ IO::Handle {
        until $body.eof {
            await $csock.write($body.read(1024));
        }
        $body.close;
    } elsif $body ~~ Channel {
        while my $got = $body.receive {
            await $csock.write($got);
        }
        CATCH { when X::Channel::ReceiveOnClosed { debug('closed channel'); } }
    } else {
        die "3rd element of response object must be instance of Array or IO::Handle or Channel";
    }

    debug "sent body" if DEBUGGING;
}

=begin pod

=head1 NAME

HTTP::Server::Tiny - HTTP server for Perl6

=head1 SYNOPSIS

    use HTTP::Server::Tiny;

    my $port = 8080;

    HTTP::Server::Tiny.new('127.0.0.1', $port).run(sub ($env) {
        my $channel = Channel.new;
        start {
            for 1..100 {
                $channel.send(($_ ~ "\n").Str.encode('utf-8'));
            }
            $channel.close;
        };
        return 200, ['Content-Type' => 'text/plain'], $channel
    });

=head1 DESCRIPTION

HTTP::Server::Tiny is tiny HTTP server library for perl6.

=head1 METHODS

=item C<HTTP::Server::Tiny.new($host, $port)>

Create new instance.

=item C<$server.run(Sub $app)>

Run http server with P6SGI app.

=head1 COPYRIGHT AND LICENSE

Copyright 2015 Tokuhiro Matsuno <tokuhirom@gmail.com>

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
