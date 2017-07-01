use v6;

use lib 't/lib';
use Test::TCP;

use Test;

use HTTP::Server::Tiny;
use HTTP::Tinyish;

plan 5;

my $port = 15555;

my $server = HTTP::Server::Tiny.new(host => '127.0.0.1', port => $port);

my $thr = Thread.start({
    $server.run(sub ($env) {
        isa-ok $env<p6w.version>, Version;
        is $env<p6w.multithread>, True;
        is $env<p6w.multiprocess>, False;
        is $env<p6w.run-once>, False;
        return 200, ['Content-Type' => 'text/plain'], ["hello\n".encode('utf-8')]
    });
}, :app_lifetime);

wait_port($port);

my $sock = IO::Socket::INET.new(
    host => '127.0.0.1',
    port => $port,
);
$sock.print("GET / HTTP/1.0\r\n\r\n");
my Str $buf;
while my $got = $sock.recv() {
    $buf ~= $got;
}
ok $buf ~~ /hello/;

done-testing;

