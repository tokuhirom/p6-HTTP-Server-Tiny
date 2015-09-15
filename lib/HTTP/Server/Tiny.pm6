use v6;
unit class HTTP::Server::Tiny;

use Raw::Socket::INET;

has $.port = 80;
has $.host = '127.0.0.1';

has $!sock;

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

method run($app) {
    say "http server is ready: http://$.host:$.port/";
    while my $csock = $!sock.accept() {
        say "receiving";
        my $buf = '';

        my $tmpbuf = Buf.new;
        $tmpbuf[1023] = 0; # extend buffer
        loop {
            my $received = $csock.recv($tmpbuf, 1024, 0);
            say "received: $received";
            # FIXME: only support utf8
            $buf ~= $tmpbuf.subbuf(0, $received).decode('utf-8');
            my ($done, $env) = self.parse-http-request($buf);
            if $done {
                say 'got http header';
                # TODO: chunked support
                # TODO: use return value
                my $res = $app($env);
                my $resp = "200 perl6\r\ncontent-type: text/plain\r\n\r\nhoge".encode('utf-8');
                $csock.send($resp, $resp.elems, 0);
                $csock.close();
                $res.perl.say;
                last;
            } else {
                $buf.say;
                say 'not yet.';
            }
        }
    }
}

# This code is just a shit. I should replace this by kazuho san's.
method parse-http-request(Str $buf) {
    if $buf ~~ m/^(<[A..Z]>+)\s(\S+)\sHTTP\/1\.(.)\r\n
        ( ( <[ A..Z a..z - ]>+ ) \s* \: \s* (.*) \r\n )*
        \r\n
    / {
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
        return (True, $env);
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
