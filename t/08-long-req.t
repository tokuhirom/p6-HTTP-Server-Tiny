use v6;

use Test;

use HTTP::Server::Tiny;
use HTTP::Tinyish;

plan 1;

my $port = 15555;

my $server = HTTP::Server::Tiny.new('127.0.0.1', $port);

Thread.start({
    $server.run(sub ($env) {
        my $body = $env<psgi.input>.slurp-rest: :bin;
        return 200, ['Content-Type' => 'text/plain'], [$body]
    });
});

my %resp = HTTP::Tinyish.new.post("http://127.0.0.1:$port/",
   headers => { 
        'content-type' => 'application/x-www-form-urlencoded'
    },
    content => "hello\n" x 1000);
is(%resp<content>.chars, 6000);

