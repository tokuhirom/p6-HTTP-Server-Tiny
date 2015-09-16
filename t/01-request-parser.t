use v6;
use Test;

use HTTP::Server::Tiny;

my $tiny = HTTP::Server::Tiny.new('127.0.0.1', 0);

# no headers
my ($ok, $env) = $tiny.parse-http-request("GET / HTTP/1.0\r\n\r\n");
ok $ok;
is $env<REQUEST_METHOD>, "GET";
is $env<PATH_INFO>, "/";

# headers
{
    my ($ok, $env) = $tiny.parse-http-request("GET / HTTP/1.0\r\ncontent-type: text/html\r\n\r\n");
    ok $ok;
    is $env<REQUEST_METHOD>, "GET";
    is $env<PATH_INFO>, "/";
    is $env<HTTP_CONTENT_TYPE>, "text/html";
}

done-testing;
