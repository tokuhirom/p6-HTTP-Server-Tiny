use v6;

my $n = 1000;

use Test;
use HTTP::Server::Tiny;

plan $n;

my $server = HTTP::Server::Tiny.new('127.0.0.1', 0);
my $port = $server.localport;

my $server-thread = Thread.start({
    $server.run-threads(10, sub ($env) {
        [200, ['Content-Type' => 'text/plain'], ["hello\n".encode('utf-8')]]
    });
    die "should not reach here";
});

sleep 0.1;
say "# started testing";
for 1..$n {
    say "# GET $_";

    my $sock = IO::Socket::INET.new(
        host => '127.0.0.1',
        port => $port
    );
    say "connected.";
    $sock.print("GET / HTTP/1.0\r\n\r\n");
    my $resp = "";
    loop {
        my $got = $sock.recv(1024);
        last if $got.chars == 0;
        say "reading next: { $got.elems }";
        $resp ~= $got;
    }
    ok $resp ~~ /hello/;
    $sock.close();
    say "# got";
    # say ($content eqv "hello\n" ?? "ok" !! "not ok") ~ " - content($_)";
}
