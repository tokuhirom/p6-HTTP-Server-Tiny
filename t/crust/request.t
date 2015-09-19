use v6;

use Test;
use Crust::Request;
use Hash::MultiValue;

my $req = Crust::Request.new({
    :REMOTE_ADDR<127.0.0.1>,
    :QUERY_STRING<foo=bar&foo=baz>,
    'psgi.input' => open('t/crust/request.t'),
    :CONTENT_TYPE<text/html>
});
is $req.address, '127.0.0.1';
my $p = $req.query_paramerters;
ok [$p.all-pairs] eqv [:foo<bar>, :foo<baz>];
is $req.headers.content-type, 'text/html';
ok $req.content ~~ /"psgi.input"/; # XXX better method?

done-testing;
