use v6;

say "1..1";

use lib 't/lib';

use Test::Utils;

use HTTP::Server::Tiny;
use LWP::Simple; # bundled

my $server = HTTP::Server::Tiny.new('127.0.0.1', 0);
my $port = $server.localport;

my $pid = fork();
if $pid == 0 { # child
    $server.run-shotgun('eg/hello.psgi6');
    die "should not reach here";
} elsif $pid > 0 { # parent
    sleep 0.1;
    my $content = LWP::Simple.get("http://127.0.0.1:$port/");
    say ($content eqv "hello!!!\n" ?? "ok" !! "not ok") ~ " - content";
    unless $content eqv "hello!!!\n" {
        say "got '$content'";
    }
    kill($pid, SIGTERM);
    waitpid($pid, 0);
} else {
    die "fork failed";
}
