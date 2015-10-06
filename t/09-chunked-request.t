use v6;

use Test;

use HTTP::Server::Tiny;
use HTTP::Tinyish;

plan 1;

my $port = 15555;

my $server = HTTP::Server::Tiny.new(host => '127.0.0.1', port => $port);

Thread.start({
    $server.run(sub ($env) {
        my $body = $env<p6sgi.input>.slurp-rest(:bin);
        return 200, ['Content-Type' => 'text/plain'], [$body]
    });
});

sleep 0.5;
my $sock = IO::Socket::INET.new(
    host => '127.0.0.1',
    port => $port,
);
for (
    "POST /resource/test HTTP/1.1\r\n",
    "User-Agent: curl/7.28.0\r\rn",
    "Host: localhost:8888\r\n",
    "Content-type: text/plain\r\n",
    "Transfer-Encoding: chunked\r\n",
    "Connection: Keep-Alive\r\n",
    "Expect: 100-continue\r\n",
    "\r\n",
    "13\r\n",
    "hogehoge1\n",
    "fugafuga1",
    "13\r\n",
    "hogehoge2\n",
    "fugafuga2",
    "13\r\n",
    "hogehoge3\n",
    "fugafuga3",
    "13\r\n",
    "hogehoge4\n",
    "fugafuga4",
    "13\r\n",
    "hogehoge5\n",
    "fugafuga5",
    "13\r\n",
    "hogehoge6\n",
    "fugafuga6",
    "13\r\n",
    "hogehoge7\n",
    "fugafuga7",
    "13\r\n",
    "hogehoge8\n",
    "fugafuga8",
    "13\r\n",
    "hogehoge9\n",
    "fugafuga9",
    "15\r\n",
    "hogehoge10\n",
    "fugafuga10",
    "0\r\n",
    ) {
    $sock.write: .encode('utf-8')
}
say "# wrote requests";
my Buf $buf .= new;
while my $got = $sock.recv(:bin) {
    $buf ~= $got;
}
ok $buf.decode('utf-8').index([
    "hogehoge1\n",
    "fugafuga1hogehoge2\n",
    "fugafuga2hogehoge3\n",
    "fugafuga3hogehoge4\n",
    "fugafuga4hogehoge5\n",
    "fugafuga5hogehoge6\n",
    "fugafuga6hogehoge7\n",
    "fugafuga7hogehoge8\n",
    "fugafuga8hogehoge9\n",
    "fugafuga9hogehoge10\n",
    "fugafuga10"
].join("")) > 0;

