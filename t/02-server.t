use v6;

use Test;

use HTTP::Server::Tiny;
use HTTP::Tinyish;

plan 1;

my $port = 15555;

my $server = HTTP::Server::Tiny.new('127.0.0.1', $port);

Thread.start({
    $server.run(sub ($env) {
        return 200, ['Content-Type' => 'text/plain'], ["hello\n".encode('utf-8')]
    });
});

my $res = HTTP::Tinyish.new.get("http://127.0.0.1:$port/");
is $res<content>, "hello\n", "content";

done-testing;

