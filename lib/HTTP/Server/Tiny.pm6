use v6;
unit class HTTP::Server::Tiny;

use Raw::Socket::INET;
use HTTP::Request::Parser;
use NativeCall;

my class IO::Scalar::Empty {
    method eof() { True }
    method read(Int(Cool:D) $bytes) {
        my $buf := buf8.new;
        return $buf;
    }
}

has $.port = 80;
has $.host = '127.0.0.1';

has $!sock;

has %pids;

has Bool $shown-banner;

sub info($message) {
    say "[INFO] [{$*THREAD.id}] $message";
}

constant DEBUGGING = %*ENV<DEBUGGING>.Bool;

macro debug($message) {
    if DEBUGGING {
        quasi {
            say "[DEBUG] [{$*THREAD.id}] " ~ {{{$message}}};
        }
    } else {
        quasi { }
    }
}

module private {
    our sub waitpid(Int $pid, CArray[int] $status, Int $options)
            returns Int is native { ... }
}

my sub fork()
    returns Int
    is native { ... }

sub waitpid(Int $pid, Int $options) {
    my $status = CArray[int].new;
    $status[0] = 0;
    my $ret_pid = private::waitpid($pid, $status, $options);
    return ($ret_pid, $status[0]);
}


method new($host, $port) {
    self.bless(host => $host, port => $port)!initialize;
}

method !initialize() {
    $!sock = Raw::Socket::INET.new(
        listen => 60,
        localhost => $.host,
        localport => $.port,
        reuseaddr => True,
    );
    self;
}

method localport() { $!sock.localport }

method run(Sub $app) {
    self!show-banner;

    loop {
        my $csock = $!sock.accept();
        LEAVE {
            CATCH { default { say "[ERROR] $_" } }
            say "closing socket";
            $csock.close
        }

        self.handler($csock, $app);

        CATCH { default { say "[ERROR] $_" } }
    }
    die "should not reach here";
}

method !show-banner() {
    unless $!shown-banner {
        say "http server is ready: http://$.host:{$!sock.localport}/";
        $!shown-banner = True;
    }
}

method run-prefork(Int $workers, Sub $app) {
    if $*DISTRO.name eq 'macosx' {
        # kqueue is not fork safe. and macosx doesn't support rfork(2).
        die "prefork is not supported on osx";
    }

    self!show-banner;

    my sub spawn-worker(Sub $code) {
        my $pid = fork();
        if $pid == 0 {
            $code();
            exit;
        } elsif $pid > 0 {
            %pids{$pid} = True;
            return;
        } else {
            die "fork failed";
        }
    }

    my $code = sub { self.run($app) };

    for 1..$workers.Int {
        spawn-worker($code);
    }

    loop {
        my ($pid, $status) = waitpid(-1, 0);
        if %pids{$pid}:exists {
            say "exited $pid: $status";
            %pids{$pid}:delete;
            spawn-worker($code);
        }
    }
}

method run-threads(Int $workers, Sub $app) {
    info("run-threads: workers:$workers");

    self!show-banner;

    my @threads;

    for 1..$workers.Int {
        @threads.push: Thread.start(sub {
            loop {
                my $csock = $!sock.accept;
                LEAVE {
                    debug "closing socket";
                    if $csock.defined {
                        $csock.close;
                    } else {
                        debug("no socket");
                    }
                    CATCH { default { say "[ERROR] in closing $_ {.backtrace.full}" } }
                }

                self.handler($csock, $app);
                CATCH { default { say "[ERROR] in handler $_{.backtrace.full}" } }
            }
            info("should not reach here");
        });
    }

    .join for @threads;
}

method run-shotgun(Str $filename) {
    self!show-banner;

    loop {
        my $csock = $!sock.accept();

        my $pid = fork();
        if ($pid > 0) { # parent
            $csock.close;
            say "waiting child process...";
            my ($got, $status) = waitpid($pid, 0);
            say "child process was terminated: $got, $status";
            if ($got < 0) {
                die "waitpid failed";
            }
        } elsif ($pid == 0) { # child
            LEAVE {
                CATCH { default { say "[ERROR] $_" } }
                say "closing socket";
                $csock.close
            }
            self.handler($csock, sub ($env) {
                my $app = EVALFILE($filename);
                return $app($env);
            });
            exit 0;
        } else {
            die "fork failed";
        }
    }
    die "should not reach here";
}

my sub nonce () { return (".{$*PID}." ~ 1000.rand.Int) }

method handler($csock, Sub $app) {
    CATCH { default { say "[wtf] $_: {.backtrace.full}" } }
    debug "receiving";
    my $buf = Buf.new;

    my $tmpbuf = Buf.new;
    $tmpbuf[1023] = 0; # extend buffer
    loop {
        my $received = $csock.recv($tmpbuf, 1024, 0);
        debug "received: $received";
        unless $received {
            debug("cannot read response. abort.");
            return;
        }
        $buf ~= $tmpbuf.subbuf(0, $received);
        my ($done, $env, $header_len) = parse-http-request($buf);
        debug("http parsing status: $done");

        # TODO: secure File::Temp
        my $tmpfile;
        LEAVE { unlink $tmpfile if $tmpfile.defined }

        if $env<CONTENT_LENGTH>.defined {
            debug('reading content body');
            $tmpfile = $*TMPDIR.child("p6-httpd" ~ nonce());
            my $input = open("$tmpfile", :rw);
            my $read = $env<CONTENT_LENGTH>.Int;

            if $buf.elems > $header_len {
                my $b = $buf.subbuf($header_len);
                $input.write($b);
                $read -= $b.elems;
            }
            while $read > 0 {
                my $received = $csock.recv($tmpbuf, 1024, 0);
                $input.write($tmpbuf.subbuf(0, $received));
                $read -= $received;
            }
            $input.seek(0, 0); # rewind

            $env<psgi.input> = $input;
        } else {
            $env<psgi.input> = IO::Scalar::Empty.new;
        }

        if $done {
            debug 'got http header';
            # TODO: chunked support
            # TODO: HTTP/1.1 support
            my $res = do {
                CATCH { default {
                    say "[app error] $_ {.backtrace.full}";
                    self!send-response($csock, [500, [], ['Internal server error'.encode('utf-8')]]);
                    return;
                } };
                $app($env);
            };
            self!send-response($csock, $res);
            return;
        } else {
            $buf.say;
            say 'not yet.';
        }
    }
}

method !send-response($csock, Array $res) {
    debug "sending response";
    my $resp_string = "HTTP/1.0 $res[0] perl6\r\n";
    for @($res[1]) {
        if .key ~~ /<[\r\n]>/ {
            die "header split";
        }
        $resp_string ~= "{.key}: {.value}\r\n";
    }
    $resp_string ~= "\r\n";
    my $resp = $resp_string.encode('ascii');
    $csock.send($resp, $resp.elems, 0);
    if $res[2].isa(Array) {
        for @($res[2]) -> $elem {
            if $elem.does(Blob) {
                $csock.send($elem, $elem.elems, 0);
            } else {
                die "response must be Array[Blob]. But {$elem.perl}";
            }
        }
    } elsif $res[2].isa(IO) {
        # TODO: support IO response
        die "IO is not supported yet";
    } else {
        die "3rd element of response object must be instance of Array or IO";
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
