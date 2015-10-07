use v6;
unit class HTTP::Server::Tiny;

use HTTP::Parser; # parse-http-request
use File::Temp;
use IO::Blob;

my Buf $CRLF = Buf.new(0x0d, 0x0a);

my class TempFile {
    has $.filename;
    has $.fh;

    method new() {
        # XXX insecure
        my $filename;
        loop {
            $filename = $*TMPDIR.child("p6-httpd" ~ nonce());
            last unless $filename.e;
        }
        my $fh = open $filename, :rw;
        debug "filename: $filename: {$fh.opened}";
        self.bless(filename => $filename, fh => $fh);
    }

    my sub nonce () { return (".{$*PID}." ~ flat('a'..'z', 'A'..'Z', 0..9, '_').roll(10).join) }

    method write(Blob $b) {
        debug "write to $.filename";
        $.fh.write($b)
    }

    method read(Int(Cool:D) $bytes) {
        $.fh.read: $bytes
    }

    method seek(Int:D $offset, Int:D $whence) {
        $.fh.seek($offset, $whence);
    }

    method tell() {
        $.fh.tell();
    }

    method slurp-rest(:$bin!) {
        $.fh.slurp-rest: bin => $bin
    }

    method close() {
        debug 'close';
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
has $.max-keepalive-reqs = 1;

sub info($message) {
    say "[INFO] [{$*PID}] [{$*THREAD.id}] $message";
}

my constant DEBUGGING = %*ENV<HST_DEBUG>.Bool;

my sub debug($message) {
    say "[DEBUG] [{$*PID}] [{$*THREAD.id}] $message" if DEBUGGING;
}

my multi sub error(Exception $err) {
    say "[ERROR] [{$*PID}] [{$*THREAD.id}] $err {$err.backtrace.full}";
}

my multi sub error(Str $err) {
    say "[ERROR] [{$*PID}] [{$*THREAD.id}] $err";
}

method !create-temp-buffer($len) {
    if $len.defined && $len < 64_000 {
        IO::Blob.new
    } else {
        TempFile.new;
    }
}


method run(HTTP::Server::Tiny:D: Callable $app) {
    # moarvm doesn't handle SIGPIPE correctly. Without this,
    # perl6 exit without any message.
    # -- tokuhirom@20151003
    signal(SIGPIPE).tap({ debug("Got SIGPIPE") }) unless $*DISTRO.is-win;

    # TODO: I want to use IO::Socket::Async#port method to use port 0.
    say "http server is ready: http://$.host:$.port/ (pid:$*PID)";

    react {
        whenever IO::Socket::Async.listen($.host, $.port) -> $conn {
            LEAVE { try $conn.close }
            self!handler($conn, $app);
        }
    }
}

method !handler(IO::Socket::Async $conn, Callable $app) {
    debug("new request");

    CATCH {
        when /^"broken pipe"$/ {
            error("broken pipe");
            return;
        }
        when X::Channel::ReceiveOnClosed {
            error("Cannot receive a message on a closed channel");
            return;
        }
        default {
            error($_);
            return;
        }
    }

    my $read-chan = $conn.bytes-supply.Channel;

    my $req-count = 0;

    my $pipelined_buf;
    loop {
        ++$req-count;

        my $may-keepalive = $req-count < $.max-keepalive-reqs;
        $may-keepalive = True if $pipelined_buf.defined && $pipelined_buf.elems > 0;
        (my $keepalive, $pipelined_buf) = self!handle-connection(
                $conn, $read-chan, $app, $may-keepalive, $req-count!=1, $pipelined_buf);
        last unless $keepalive;
    };
}

method !handle-connection($conn, $read-chan, Callable $app, Bool $use-keepalive is copy, Bool $is-keepalive,
        $prebuf is copy) {
    my $pipelined_buf;
    my Buf $buf .= new;
    my Hash $env;
    LEAVE { try $env<p6sgi.input>.close }

    # read headers
    loop {
        if $prebuf {
            $buf ~= $prebuf;
            $prebuf = Nil;
        } else {
            debug 'reading header';
            $buf ~= $read-chan.receive;
        }

        debug 'parsing http request';
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

    $env<SERVER_NAME> = $.host;
    $env<SERVER_PORT> = $.port;
    $env<SCRIPT_NAME> = '';
    $env<psgi.error>  = $*ERR;

    # TODO: REMOTE_ADDR
    # TODO: REMOTE_PORT

    my $content-length = $env<CONTENT_LENGTH>;
    if $content-length.defined {
        $content-length .= Int;
    }

    my $protocol = $env<SERVER_PROTOCOL>;
    if $use-keepalive {
        if $protocol eq 'HTTP/1.1' {
            if my $c = $env<HTTP_CONNECTION> {
                if $c ~~ m:i/^\s*close\s*/ {
                    $use-keepalive = False;
                }
            }
        } else {
            if my $c = $env<HTTP_CONNECTION> {
                unless $c ~~ m:i/^\s*keep\-alive\s*/ {
                    $use-keepalive = False;
                }
            } else {
                $use-keepalive = False;
            }
        }
    }

    $env<p6sgi.input> = self!create-temp-buffer($content-length);

    debug "content-length: {$content-length.perl}";

    my Bool $chunked = $env<HTTP_TRANSFER_ENCODING>
        ?? $env<HTTP_TRANSFER_ENCODING>.lc eq 'chunked'
        !! False;

    if $content-length.defined {
        my $cl = $content-length;
        while $cl > 0 {
            if $buf.elems > 0 {
                debug "got {$buf.elems} bytes";
                my $write-bytes = $buf.elems min $cl;
                $env<p6sgi.input>.write($buf.subbuf(0, $write-bytes)); # XXX blocking
                $cl -= $write-bytes;
                debug "remains $cl";
                last unless $cl > 0;
            }

            $buf ~= $read-chan.receive;
        }
    } elsif $chunked {
        my $wrote = 0;
        my $chunk;
        DECHUNK: loop {
            debug 'processing chunk';
            if $buf.elems > 0 {
                $chunk = $buf;
                $buf = Buf.new;
            } else {
                debug "read chunk data";
                $chunk = $read-chan.receive;
            }

            PROCESS_CHUNK: loop {
                my int $end_pos = 0;
                my Buf $end_marker = Buf.new(13, 10);
                while $end_pos < $chunk.bytes {
                    if ($end_marker eq $chunk.subbuf($end_pos, 2)) {
                        debug 'found chunk marker';
                        my $size = $chunk.subbuf(0, $end_pos);
                        my $chunk_len = :16($size.decode('ascii'));
                        debug "got chunk {$end_pos+2} + $chunk_len {$chunk.elems}";
                        if $chunk_len == 0 {
                            debug "end chunk";
                            last DECHUNK;
                        }
                        if $end_pos+2+$chunk_len <= $chunk.elems {
                            debug 'writing temp file';
                            $env<p6sgi.input>.write($chunk.subbuf($end_pos+2, $chunk_len));
                            $wrote += $chunk_len;
                            $chunk = $chunk.subbuf($end_pos+2 + $chunk_len);
                            next PROCESS_CHUNK;
                        }
                    }
                    $end_pos++;
                }
                last;
            }
        }
        debug "wrote $wrote bytes by chunked";
        $env<CONTENT_LENGTH> = $wrote.Str;
    } else {
        # TODO: chunked request support
        if $buf.decode('ascii') ~~ /^[GET|HEAD]/ { # pipeline
            $pipelined_buf = $buf;
            $use-keepalive = True; # force keep-alive
        }
    }

    my @res;

    if $env<HTTP_EXPECT> {
        if $env<HTTP_EXPECT> eq '100-continue' {
            await $conn.write("HTTP/1.1 100 Continue\r\n\r\n".encode('ascii'));
        } else {
            @res = 417,[ 'Content-Type' => 'text/plain', 'Connection' => 'close' ], [ 'Expectation Failed'.encode('utf-8') ] 
        }
    }

    $env<p6sgi.input>.seek(0,0); # rewind

    debug 'run app';
    my ($status, $headers, $body) = sub {
        if @res {
            return @res;
        }
        CATCH {
            default {
                error($_);
                return 500, [], ['Internal Server Error!'.encode('utf-8')];
            }
        };
        return $app.($env);
    }.();

    debug 'sending response';
    $use-keepalive = self!handle-response($conn, $protocol, $status, $headers, $body, $use-keepalive);

    return $use-keepalive, $pipelined_buf;
}

my @WDAY = <Sun Mon Tue Wed Thu Fri Sat Sun>;
my @MON = <Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec>;
my sub http-date() {
    my $dt = DateTime.now;
    return sprintf("%s, %02d-%s-%04d %02d:%02d:%02d GMT",
            @WDAY[$dt.day-of-week], $dt.day-of-month, @MON[$dt.month-1], $dt.year,
            $dt.hour, $dt.minute, $dt.second);
}

method !handle-response($csock, $protocol, $status, $headers, $body, $use-keepalive is copy) {
    debug "sending response";

    my $resp_string = "$protocol $status perl6\r\n";
    my %send_headers;
    for @($headers) {
        if .key ~~ /<[\r\n]>/ {
            die "header split";
        }

        my $lck = .key.lc;
        if ($lck eq 'connection') {
            if $use-keepalive && .value.lc ne 'keep-alive' {
                $use-keepalive = False;
            }
        } else {
            $resp_string ~= "{.key}: {.value}\r\n";
        }

        %send_headers{$lck} = .value;
    }
    unless %send_headers<server> {
        $resp_string ~= "server: $.server-software\r\n";
    }
    unless %send_headers<date> {
        $resp_string ~= "date: {http-date}\r\n";
    }

    my sub status-with-no-entity-body(int $status) {
        return $status < 200 || $status == 204 || $status == 304;
    }

    # try to set content-length when keepalive can be used, or disable it
    my $use-chunked = False;
    if $protocol eq 'HTTP/1.0' {
        if $use-keepalive {
            # Plack::Util::content_length
            my sub content-length($body) {
                return Nil unless defined $body;
                if $body ~~ Array {
                    my $cl = 0;
                    for @($body) {
                        $cl += .bytes;
                    }
                    return $cl;
                } elsif $body ~~ IO::Handle {
                    return $body.s;
                }
            }

            if %send_headers<content-length>.defined && %send_headers<transfer-encoding>.defined {
                # ok
            } elsif !status-with-no-entity-body($status) && (my $cl = content-length($body)) {
                $resp_string ~= "content-length: $cl\015\012";
            } else {
                $use-keepalive = False;
            }

            $resp_string ~= "Connection: keep-alive\x0d\x0a" if $use-keepalive;
            $resp_string ~= "Connection: close\x0d\x0a" unless $use-keepalive; # fmm
        }
    } elsif ( $protocol eq 'HTTP/1.1' ) {
        if %send_headers<content-length>.defined || %send_headers<transfer-encoding>.defined {
            # ok
        } elsif !status-with-no-entity-body($status) {
            $resp_string ~= "Transfer-Encoding: chunked\x0d\x0a";
            $use-chunked = True;
        }
        $resp_string ~= "Connection: close\x0d\x0a" unless $use-keepalive; # fmm
    }
    $resp_string ~= "\r\n";
    
    # TODO combine response header and small request body

    my $resp = $resp_string.encode('ascii');
    await $csock.write($resp);

    debug "sent header";

    my sub scan-psgi-body($body) {
        gather {
            if $body ~~ Array {
                for @($body) -> $elem {
                    if $elem ~~ Blob {
                        take $elem;
                    } else {
                        die "response must be Array[Blob]. But {$elem.perl}";
                    }
                }
            } elsif $body ~~ IO::Handle {
                until $body.eof {
                    take $body.read(1024);
                }
                $body.close;
            } elsif $body ~~ Channel {
                while my $got = $body.receive {
                    take $got;
                }
                CATCH { when X::Channel::ReceiveOnClosed { debug('closed channel'); } }
            } else {
                die "3rd element of response object must be instance of Array or IO::Handle or Channel";
            }
        }
    }

    for scan-psgi-body($body) -> Blob $got {
        next if $got.bytes == 0;

        if $use-chunked {
            my $buf = sprintf("%X", $got.bytes).encode('ascii') ~ $CRLF ~ $got ~ $CRLF;
            await $csock.write($buf);
        } else {
            await $csock.write($got);
        }
    }
    if $use-chunked {
        debug "send end mark";
        await $csock.write("0".encode('ascii') ~ $CRLF ~ $CRLF);
    }

    debug "sent body" if DEBUGGING;

    return $use-keepalive;
}

=begin pod

=head1 NAME

HTTP::Server::Tiny - a simple HTTP server for Perl6

=head1 SYNOPSIS

    use HTTP::Server::Tiny;

    my $port = 8080;

    HTTP::Server::Tiny.new(host => '127.0.0.1', port => $port).run(sub ($env) {
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

HTTP::Server::Tiny is a standalone HTTP/1.1 web server for perl6.

=head1 METHODS

=item C<HTTP::Server::Tiny.new($host, $port)>

Create new instance.

=item C<$server.run(Callable $app)>

Run http server with P6SGI app.

=head1 TODO

=item Support timeout

=head1 COPYRIGHT AND LICENSE

Copyright 2015 Tokuhiro Matsuno <tokuhirom@gmail.com>

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
