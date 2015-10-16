use v6;

use HTTP::Server::Tiny;

my $port = 15555;

my $httpd = HTTP::Server::Tiny.new(
    host => '127.0.0.1',
    port => $port,
    max-keepalive-reqs => (%*ENV<KEEPALIVE> // 1000).Int,
);
$httpd.run(sub ($env) {
    return 200, ['Content-Type' => 'text/plain'], ['ok']
});

