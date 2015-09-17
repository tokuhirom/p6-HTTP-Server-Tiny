use v6;

say "1..1";

use lib 't/lib';

use Test::Utils;

use NativeCall;
use HTTP::Server::Tiny;
use LWP::Simple; # bundled

my $server = HTTP::Server::Tiny.new('127.0.0.1', 0);
my $port = $server.localport;

my $pid = fork();
if $pid == 0 { # child
    $server.run(sub ($env) {
        my $body = $env<psgi.input>.slurp-rest;
        [200, ['Content-Type' => 'text/plain'], [$body.encode('utf-8')]]
    });
    exit;
} elsif $pid > 0 { # parent
    sleep 0.1;
    my $content = LWP::Simple.post("http://127.0.0.1:$port/", {
        'content-type' => 'application/x-www-form-urlencoded'
    }, 'foo=bar');
    say ($content eqv "foo=bar" ?? "ok" !! "not ok") ~ " - content";
    kill($pid, SIGTERM);
    waitpid($pid, 0);
} else {
    die "fork failed";
}
