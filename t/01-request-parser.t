use v6;
use Test;

use HTTP::Request::Parser;

# no headers
my ($ok, $env) = parse-http-request("GET / HTTP/1.0\r\n\r\n".encode('ascii'));
ok $ok;
is $env<REQUEST_METHOD>, "GET";
is $env<PATH_INFO>, "/";

# headers
{
    my ($ok, $env) = parse-http-request("GET / HTTP/1.0\r\ncontent-type: text/html\r\n\r\n".encode('ascii'));
    ok $ok;
    is $env<REQUEST_METHOD>, "GET";
    is $env<PATH_INFO>, "/";
    is $env<HTTP_CONTENT_TYPE>, "text/html";
}

done-testing;
