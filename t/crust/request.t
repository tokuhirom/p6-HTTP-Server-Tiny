use v6;

use Test;
use Crust::Request;
use Hash::MultiValue;

{
    my $req = Crust::Request.new({
        :REMOTE_ADDR<127.0.0.1>,
        :QUERY_STRING<foo=bar&foo=baz>,
        'psgi.input' => open('t/crust/request.t'),
        :HTTP_USER_AGENT<hoge>,
        :CONTENT_TYPE<text/html>
    });
    is $req.address, '127.0.0.1';
    my $p = $req.query_paramerters;
    ok [$p.all-pairs] eqv [:foo<bar>, :foo<baz>];
    is $req.headers.content-type, 'text/html';
    is $req.user-agent, 'hoge';
    ok $req.content ~~ /"psgi.input"/; # XXX better method?
}

# body-parameters: x-www-form-urlencoded
{
    my $req = Crust::Request.new({
        :REMOTE_ADDR<127.0.0.1>,
        :QUERY_STRING<foo=bar&foo=baz>,
        'psgi.input' => open('t/dat/query.txt'),
        :HTTP_USER_AGENT<hoge>,
        :CONTENT_TYPE<application/x-www-form-urlencoded>
    });
    is $req.body-parameters<iyan>, 'bakan';
}

done-testing;
