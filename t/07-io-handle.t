use v6;
# HELLO

use Test;

use HTTP::Server::Tiny;
use HTTP::Tinyish;

plan 1;

my $port = 15555;

my $server = HTTP::Server::Tiny.new(host => '127.0.0.1', port => $port);

Thread.start({
    $server.run(sub ($env) {
        my $fh = open 't/07-io-handle.t', :r;
        return 200, ['Content-Type' => 'text/plain'], $fh
    });
});

my $resp = HTTP::Tinyish.new.post("http://127.0.0.1:$port/",
   headers => { 
        'content-type' => 'application/x-www-form-urlencoded'
    },
    content => 'foo=bar');
ok $resp<content> ~~ /HELLO/;

