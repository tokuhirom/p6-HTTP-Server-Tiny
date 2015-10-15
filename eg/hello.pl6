use v6;

use HTTP::Server::Tiny;

my $port = 15555;

HTTP::Server::Tiny.new(host => '127.0.0.1', port => $port).run(sub ($env) {
    return 200, ['Content-Type' => 'text/plain'], ['ok']
});

