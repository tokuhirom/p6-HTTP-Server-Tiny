[![Build Status](https://travis-ci.org/tokuhirom/p6-HTTP-Server-Tiny.svg?branch=master)](https://travis-ci.org/tokuhirom/p6-HTTP-Server-Tiny)

NAME
====

HTTP::Server::Tiny - a simple HTTP server for Perl6

SYNOPSIS
========

    use HTTP::Server::Tiny;

    my $port = 8080;

    # Only listen for connections from the local host
    # if you want this to be accessible from another
    # host then change this to '0.0.0.0'
    my $host = '127.0.0.1';

    HTTP::Server::Tiny.new(:$host , :$port).run(sub ($env) {
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

  * `$server.run(Callable $app, Promise :$control-promise)`

Run http server with P6W app. The named parameter `control-promise` if provided, can be *kept* to quit the server loop, which may be useful if the server is run asynchronously to the main thread of execution in an application.

If the optional named parameter `control-promise` is provided with a `Promise` then the server loop will be quit when the promise is kept.

VERSIONING RULE
===============

This module respects [Semantic versioning](http://semver.org/)

TODO
====

  * Support timeout

COPYRIGHT AND LICENSE
=====================

Copyright 2015, 2016 Tokuhiro Matsuno <tokuhirom@gmail.com>

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.
