use v6;

use Test;
use lib 't/lib';
use Test::TCP;
use HTTP::Server::Tiny;
use HTTP::Tinyish;
use IO::Blob;

plan 3;

my $port = 15555;

my $server = HTTP::Server::Tiny.new(host => '127.0.0.1', port => $port);

my $io = IO::Blob.new();
$*ERR = $io;

Thread.start({
    $server.run(sub ($env) {
        $env<p6w.errors>.emit("foo");
        $env<p6w.errors>.emit("bar");
        $env<p6w.errors>.emit("baz\nval");
        return start {
            200,
            ['Content-Type' => 'application/json'],
            ['hello']
        };
    });
}, :app_lifetime);

wait_port($port);

my $resp = HTTP::Tinyish.new.get("http://127.0.0.1:$port/");
ok $resp<success>;
is $resp<content>, 'hello';

$io.seek(0);
is $io.slurp-rest, "foo\nbar\nbaz\nval\n";
