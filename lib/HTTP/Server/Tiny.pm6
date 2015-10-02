use v6;
unit class HTTP::Server::Tiny;

use HTTP::Parser; # parse-http-request
use File::Temp;
use IO::Blob;

has $.port = 80;
has $.host = '127.0.0.1';
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

method run(HTTP::Server::Tiny:D: Sub $app) {
    # moarvm doesn't handle SIGPIPE correctly. Without this,
    # perl6 exit without any message.
    # -- tokuhirom@20151003
    signal(SIGPIPE).tap({ debug("Got SIGPIPE") });

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

            my $byte-supply-tap = $conn.bytes-supply.tap(sub ($got) {
                CATCH {
                    when /^"broken pipe"$/ {
                        error("broken pipe");
                        $byte-supply-tap.close;
                    }
                    default {
                        error($_);
                        $byte-supply-tap.close;
                    }
                }

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
                        $byte-supply-tap.close;
                        return;
                    }

                    $buf = $buf.subbuf($header_len);

                    $env = $got-env;
                    $header-parsed = True;
                }

                # TODO: use Stream::Buffered
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

                my ($status, $headers, $body) = run-app($env);

                self!send-response($conn, $status, $headers, $body);

                $byte-supply-tap.close;
            }, done => sub {
                debug "DONE";
            }, quit => sub {
                debug 'quit';
            }, closing => sub {
                debug 'closing';
                {
                    $conn.close;
                    CATCH { default { debug $_ } }
                }
                if $env<psgi.input> {
                    $env<psgi.input>.close;
                }
                if $tmpfh {
                    $tmpfh.close;
                }
                if $tmpfname.IO.e {
                    unlink $tmpfname;
                }
            });
        }
    }
}

my sub nonce () { return (".{$*PID}." ~ flat('a'..'z', 'A'..'Z', 0..9, '_').roll(10).join) }

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
