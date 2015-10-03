[![Build Status](https://travis-ci.org/tokuhirom/p6-HTTP-Server-Tiny.svg?branch=master)](https://travis-ci.org/tokuhirom/p6-HTTP-Server-Tiny)

NAME
====

HTTP::Server::Tiny - a simple HTTP server for Perl6

SYNOPSIS
========

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

DESCRIPTION
===========

HTTP::Server::Tiny is a standalone HTTP/1.1 web server for perl6.

METHODS
=======

  * `HTTP::Server::Tiny.new($host, $port)`

Create new instance.

  * `$server.run(Sub $app)`

Run http server with P6SGI app.

TODO
====

  * Support timeout

COPYRIGHT AND LICENSE
=====================

Copyright 2015 Tokuhiro Matsuno <tokuhirom@gmail.com>

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.
