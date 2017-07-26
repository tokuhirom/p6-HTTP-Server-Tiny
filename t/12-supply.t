use v6;

use Test;
use lib 't/lib';
use Test::TCP;

use HTTP::Server::Tiny;
use HTTP::Tinyish;

plan 2;

my $port = 15555;

my $server = HTTP::Server::Tiny.new(host => '127.0.0.1', port => $port);

my $served-reply-ok = Promise.new;;

# Start timeout
Promise.in(5).then: {  skip-rest "Test timed out!"; exit 1;  }

Thread.start({
    $server.run(sub ($env) {
        $served-reply-ok.keep(True);
        my $s = Supply.from-list((1..100).map: *.Str.encode);
        return start { 200, ['Content-Type' => 'text/plain'], $s };
    });
}, :app_lifetime);

wait_port($port);
my $prog = $*PROGRAM.parent.child('bin/test-client').Str;

my @include = $*REPO.repo-chain.map(*.path-spec);
my $resp = run($*EXECUTABLE, '-I' «~« @include, $prog, $port, :out).out.slurp-rest;

is($resp.chomp, "123456789101112131415161718192021222324252627282930313233343536373839404142434445464748495051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899100");

is await($served-reply-ok), True, "Server served request";
