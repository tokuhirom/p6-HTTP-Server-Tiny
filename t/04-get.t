use v6;

say "1..1";

use lib 't/lib';

use Test::Utils;

use HTTP::Server::Tiny;
use LWP::Simple; # bundled
use JSON::Tiny;

my $server = HTTP::Server::Tiny.new('127.0.0.1', 0);
my $port = $server.localport;

my $pid = fork();
if $pid == 0 { # child
    $server.run(sub ($env) {
        my $json = to-json({
            PATH_INFO    => $env<PATH_INFO>,
            QUERY_STRING => $env<QUERY_STRING>,
        });

        [
            200,
            ['Content-Type' => 'application/json'],
            [$json.encode('utf-8')]
        ]
    });
    exit;
} elsif $pid > 0 { # parent
    sleep 0.1;
    my $content = LWP::Simple.get("http://127.0.0.1:$port/goo?foo=bar");
    my $dat = from-json($content);
    my $expected = {
        PATH_INFO    => '/goo',
        QUERY_STRING => 'foo=bar',
    };
    if $dat eqv $expected {
        say "ok - content";
    } else {
        say "not ok - content";
        say "got: {$dat.perl}";
    }
    kill($pid, SIGTERM);
    waitpid($pid, 0);
} else {
    die "fork failed";
}
