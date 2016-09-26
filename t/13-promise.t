#!/usr/bin/env perl6

use v6.c;

use Test;

plan 3;

use HTTP::Server::Tiny;

my $control-promise = Promise.in(2);

my $server-promise = start {
    HTTP::Server::Tiny.new(port => 11273).run(sub ($env) { }, :$control-promise);
}

my $timeout-promise = Promise.in(15);

await Promise.anyof($server-promise, $timeout-promise);

ok $control-promise, "control-promise is kept";
ok $server-promise, "server completed on command";
nok $timeout-promise, "and just to be sure it didn't timeout";

done-testing;
# vim: expandtab shiftwidth=4 ft=perl6
