use v6;

use HTTP::Server::Tiny;

sub MAIN(int $port = 5000, int :$timeout=7) {
    my $httpd = HTTP::Server::Tiny.new(host => '127.0.0.1', port => $port);
    $httpd.timeout = $timeout;
    $httpd.run(sub ($env) {
        my $secs = $env<PATH_INFO>.subst(/\//, '').Int;
        say "sleep $secs";
        sleep $secs;
        return 200, ['Content-Type' => 'text/plain'], ["OK".encode('ascii')]
    });
}

