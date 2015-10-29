use v6;

use lib 't/lib';
use Test::TCP;

use Test;

use HTTP::Server::Tiny;
use HTTP::Tinyish;

plan 1;

my $port = 15555;

my $server = HTTP::Server::Tiny.new(host => '127.0.0.1', port => $port);

my $thr = Thread.start({
    $server.run(sub ($env) {
        return 200, ['Content-Type' => 'text/plain'], ["hello\n".encode('utf-8')]
    });
});

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

exit 0; # There is no way to kill the server thread.
