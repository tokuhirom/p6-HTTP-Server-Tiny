use v6;

use HTTP::Server::Tiny;

my $port = 5000;

HTTP::Server::Tiny.new(host => '127.0.0.1', port => $port).run(sub ($env) {
    my $msg = "Hello world".encode('utf-8');
    return 200, ['Content-Type' => 'text/plain', 'content-length' => $msg.bytes], [$msg ]
});

