use v6;

use Test;
use lib 't/lib';
use Test::TCP;
use HTTP::Server::Tiny;
use HTTP::Tinyish;

plan 1;

my $port = 15555;

my $server = HTTP::Server::Tiny.new(host => '127.0.0.1', port => $port);

Thread.start({
    $server.run(sub ($env) {
        die;
    });
});

wait_port($port);
my $resp = HTTP::Tinyish.new.get("http://127.0.0.1:$port/goo?foo=bar");
is $resp<content>, 'Internal Server Error!';

