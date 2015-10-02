use v6;

use HTTP::Server::Tiny;

my $port = 5000;

HTTP::Server::Tiny.new('127.0.0.1', $port).run(sub ($env) {
    return 200, ['Content-Type' => 'text/plain'], ["Hello world".encode('utf-8')]
});

