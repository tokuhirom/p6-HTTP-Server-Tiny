use v6;
unit class HTTP::Server::Tiny;

use Raw::Socket::INET;
use NativeCall;

has $.port = 80;
has $.host = '127.0.0.1';

has $!sock;

has %pids;

has Bool $shown-banner;

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
    self!show-banner;

    for 1..$workers.Int {
        self!spawn-worker($app);
    }

    loop {
        my ($pid, $status) = waitpid(-1, 0);
        if %pids{$pid}:exists {
            %pids.delete($pid);
            self!spawn-worker($app);
        }
    }
}

method !spawn-worker(Sub $app) {
    my $pid = fork();
    if $pid == 0 {
        self.run($app);
    } elsif $pid > 0 {
        %pids{$pid} = True;
        return;
    } else {
        die "fork failed";
    }
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

method handler($csock, Sub $app) {
    CATCH { default { say "[wtf]" } }
    say "receiving";
    my $buf = '';

    my $tmpbuf = Buf.new;
    $tmpbuf[1023] = 0; # extend buffer
    loop {
        my $received = $csock.recv($tmpbuf, 1024, 0);
        say "received: $received";
        # FIXME: only support utf8
        $buf ~= $tmpbuf.subbuf(0, $received).decode('utf-8');
        my ($done, $env, $header_len) = self.parse-http-request($buf);
        # TODO: support psgix.input
        if $done {
            say 'got http header';
            # TODO: chunked support
            # TODO: HTTP/1.1 support
            my $res = do {
                CATCH { default {
                    say "[app error] $_";
                    self!send-response($csock, [500, [], ['ISE']]);
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
    say "sending response";
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

# TODO: This code is just a shit. I should replace this by kazuho san's.
method parse-http-request(Str $buf) {
    if $buf ~~ m/^(<[A..Z]>+)\s(\S+)\sHTTP\/1\.(.)\r\n
        ( ( <[ A..Z a..z - ]>+ ) \s* \: \s* (.*) \r\n )*
        \r\n
    / {
        my $header_len = $<>.elems;
        my ($method, $path_info, $version) = @($/);
        my $env = {
            REQUEST_METHOD => $method.Str,
            PATH_INFO => $path_info.Str,
        };
        for @($/[3]) {
            my ($k, $v) = @$_;
            $k = $k.subst(/\-/, '_', :g);
            $k = $k.uc;
            $env{'HTTP_' ~ $k} = $v;
        }
        return (True, $env, $header_len);
    }
    return (False, );
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
