use v6;

use Test;
use Crust::Shotgun;

my $resp = make-shotgun-app('t/psgi/hello.psgi6');
is-deeply $resp, [200, [], ['hello'.encode('utf-8')]];

done-testing;
