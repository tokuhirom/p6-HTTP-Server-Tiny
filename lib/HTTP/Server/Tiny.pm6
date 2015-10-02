use v6;
unit class HTTP::Server::Tiny;

use HTTP::Parser; # parse-http-request
use File::Temp;
use IO::Blob;

has $.port = 80;
has $.host = '127.0.0.1';

sub info($message) {
    say "[INFO] [{$*THREAD.id}] $message";
}

my constant DEBUGGING = %*ENV<HST_DEBUG>.Bool;

my sub debug($message) {
    say "[DEBUG] [{$*PID}] [{$*THREAD.id}] $message" if DEBUGGING;
}

my sub error($err) {
    say "[{$*THREAD.id}] [ERROR] $err {$err.backtrace.full}";
}

method new($host, $port) {
    self.bless(host => $host, port => $port);
}

method run(Sub $app) {
    my sub run-app($env) {
        CATCH {
            error($_);
            return 500, [], ['Internal Server Error!'];
        };
        return $app.($env);
    };

    # TODO: I want to use IO::Socket::Async#port method to use port 0.
    say "http server is ready: http://$.host:$.port/";

    react {
        whenever IO::Socket::Async.listen($.host, $.port) -> $conn {
            debug("new request");
            my Buf $buf .= new;
            my $header-parsed = False;

            my $tmpfname = $*TMPDIR.child("p6-httpd" ~ nonce());
            # LEAVE { try unlink $tmpfname }
            my $tmpfh;

            my Hash $env;
            my $got-content-len = 0;

            my $tap = $conn.bytes-supply.tap(sub ($got) {
                $buf ~= $got;
                debug("got");

                unless $header-parsed {
                    my ($header_len, $got-env) = parse-http-request($buf);
                    debug("http parsing status: $header_len");
                    if $header_len == -1 { # incomplete header
                        return;
                    }
                    if $header_len == -2 { # invalid request
                        await $conn.print("400 Bad Request\r\n\r\nBad request");
                        $conn.close;
                        return;
                    }

                    $buf = $buf.subbuf($header_len);

                    $env = $got-env;
                    $header-parsed = True;
                }

                if $buf.elems > 0 {
                    $tmpfh //= open($tmpfname, :rw);
                    $tmpfh.write($buf); # XXX blocking
                    $got-content-len += $buf.bytes;
                    $buf = Buf.new;
                }

                if $env<CONTENT_LENGTH>.defined {
                    my $cl = $env<CONTENT_LENGTH>.Int;
                    unless $cl == $got-content-len {
                        return;
                    }
                    $tmpfh.seek(0,0); # rewind
                    $env<psgi.input> = $tmpfh;
                } else {
                    # TODO: chunked request support
                    $env<psgi.input> = IO::Blob.new;
                }

                CATCH { default { error($_) } }

                my ($status, $headers, $body) = run-app($env);

                if $tmpfh {
                    $tmpfh.close;
                }
                try unlink $tmpfname;

                self!send-response($conn, $status, $headers, $body);
                
                debug("done");
                $conn.close; # TODO: keep-alive

                $env<psgi.input>.close;
                if $tmpfname.IO.e {
                    unlink $tmpfname;
                }
            }, done => sub {
                debug "DONE";
            }, quit => sub {
                debug 'quit';
            }, closing => sub {
                debug 'closing';
            });
        }
    }
}

my sub nonce () { return (".{$*PID}." ~ flat('a'..'z', 'A'..'Z', 0..9, '_').roll(10).join) }

method !send-response($csock, $status, $headers, $body) {
    debug "sending response";

    my $resp_string = "HTTP/1.0 $status perl6\r\n";
    for @($headers) {
        if .key ~~ /<[\r\n]>/ {
            die "header split";
        }
        $resp_string ~= "{.key}: {.value}\r\n";
    }
    $resp_string ~= "\r\n";
    my $resp = $resp_string.encode('ascii');
    await $csock.write($resp);

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
}

=begin pod

=head1 NAME

HTTP::Server::Tiny - blah blah blah

=head1 SYNOPSIS

  use HTTP::Server::Tiny;

=head1 DESCRIPTION

HTTP::Server::Tiny is ...

=head1 COPYRIGHT AND LICENSE

Copyright 2015 Tokuhiro Matsuno <tokuhirom@gmail.com>

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
