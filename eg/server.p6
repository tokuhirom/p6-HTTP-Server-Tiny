use v6;

use lib 'lib';

use HTTP::Server::Tiny;

sub MAIN(Str $appfile, Str $host='127.0.0.1', Int :$port=5000, Bool :$shotgun=False) {
    my $httpd = HTTP::Server::Tiny.new($host, $port);
    if $shotgun {
        $httpd.run-shotgun($appfile);
    } else {
        $httpd.run(EVALFILE($appfile));
    }
}

