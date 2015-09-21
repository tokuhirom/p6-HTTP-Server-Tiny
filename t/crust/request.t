use v6;

use Test;
use Crust::Request;
use Hash::MultiValue;

subtest {
    my $req = Crust::Request.new({
        :REMOTE_ADDR<127.0.0.1>,
        :QUERY_STRING<foo=bar&foo=baz>,
        'psgi.input' => open('t/crust/request.t'),
        :HTTP_USER_AGENT<hoge>,
        :HTTP_HEADER_REFERER<http://mixi.jp>,
        :CONTENT_TYPE<text/html>
    });
    is $req.address, '127.0.0.1';
    my $p = $req.query-paramerters;
    ok [$p.all-pairs] eqv [:foo<bar>, :foo<baz>];
    is $req.headers.content-type, 'text/html';
    is $req.header('content-type'), 'text/html';
    is $req.user-agent, 'hoge';
    is $req.referer, 'http://mixi.jp';
    ok $req.content ~~ /"psgi.input"/; # XXX better method?
    is $req.parameters<foo>, 'baz';
}, 'query params and basic things';

# body-parameters: x-www-form-urlencoded
subtest {
    my $req = Crust::Request.new({
        :REMOTE_ADDR<127.0.0.1>,
        :QUERY_STRING<foo=bar&foo=baz>,
        'psgi.input' => open('t/dat/query.txt'),
        :HTTP_USER_AGENT<hoge>,
        :CONTENT_TYPE<application/x-www-form-urlencoded>
    });
    is $req.body-parameters<iyan>, 'bakan';
    is $req.parameters<foo>, 'baz';
    is $req.parameters<iyan>, 'bakan';
}, 'body-params';

done-testing;
