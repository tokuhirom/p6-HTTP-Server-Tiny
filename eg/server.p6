use v6;

use lib 'lib';

use HTTP::Server::Tiny;

sub MAIN(Str $host='127.0.0.1', Int $port=10080) {
    my $httpd = HTTP::Server::Tiny.new($host, $port);
    $httpd.run(-> $env {
    });
}

