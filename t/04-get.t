use v6;

use Test;
use JSON::Fast;
use lib 't/lib';
use Test::TCP;
use HTTP::Server::Tiny;
use HTTP::Tinyish;

plan 1;

my $port = 15555;

my $server = HTTP::Server::Tiny.new(host => '127.0.0.1', port => $port);

Thread.start({
    $server.run(sub ($env) {
        my $json = to-json({
            PATH_INFO    => $env<PATH_INFO>,
            QUERY_STRING => $env<QUERY_STRING>,
        });

        return start {
            200,
            ['Content-Type' => 'application/json'],
            [$json.encode('utf-8')]
        };
    });
}, :app_lifetime);

wait_port($port);
my $resp = HTTP::Tinyish.new.get("http://127.0.0.1:$port/goo?foo=bar");
my $dat = do {
    CATCH { default { say "ERROR: $_"; $resp.perl.say; fail; } }
    from-json($resp<content>);
};
my $expected = {
    PATH_INFO    => '/goo',
    QUERY_STRING => 'foo=bar',
};
is-deeply $dat, $expected;

