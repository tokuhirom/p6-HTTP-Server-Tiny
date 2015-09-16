use v6;

use lib 'lib';

use HTTP::Server::Tiny;

sub MAIN(Str $appfile, Str $host='127.0.0.1', Int :$port=5000, Bool :$shotgun=False, Int :$workers=1) {
    my $httpd = HTTP::Server::Tiny.new($host, $port);
    if $shotgun {
        $httpd.run-shotgun($appfile);
    } else {
        if $workers > 1 {
            $httpd.run-prefork($workers, EVALFILE($appfile));
        } else {
            $httpd.run(EVALFILE($appfile));
        }
    }
}

