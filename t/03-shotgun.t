use v6;

say "1..1";

use NativeCall;
use HTTP::Server::Tiny;
use LWP::Simple; # bundled

module private {
    our sub waitpid(Int $pid, CArray[int] $status, Int $options)
            returns Int is native { ... }
}

sub fork()
    returns Int
    is native { ... }

sub waitpid(Int $pid, Int $options) {
    my $status = CArray[int].new;
    $status[0] = 0;
    my $ret_pid = private::waitpid($pid, $status, $options);
    return ($ret_pid, $status[0]);
}

constant SIGTERM = 15;

sub kill(int $pid, int $sig)
    returns Int
    is native { ... }

my $server = HTTP::Server::Tiny.new('127.0.0.1', 0);
my $port = $server.localport;

my $pid = fork();
if $pid == 0 { # child
    $server.run-shotgun('eg/hello.psgi6');
    die "should not reach here";
} elsif $pid > 0 { # parent
    sleep 0.1;
    my $content = LWP::Simple.get("http://127.0.0.1:$port/");
    say ($content eqv "hello\n" ?? "ok" !! "not ok") ~ " - content";
    kill($pid, SIGTERM);
    waitpid($pid, 0);
} else {
    die "fork failed";
}
