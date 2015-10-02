use HTTP::Server::Async;

my $s = HTTP::Server::Async.new(port => 5000);
$s.handler(sub ($request, $response) {
    $response.headers<Content-Type> = 'text/plain';
    $response.status = 200;
    $response.close("Hello world!");
});
await $s.listen();

