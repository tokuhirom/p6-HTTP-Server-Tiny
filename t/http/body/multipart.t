use v6;

use Test;

use HTTP::Body::Multipart;

my @headers;
my $parser = HTTP::Body::Multipart.new(
    boundary => 'LYNX'.encode('ascii'),
    on_header => sub (@h) {
        @h.perl.say;
    },
    on_body => sub ($chunk, $finished) {
        say 'on-body ------------------------------';
        $chunk.decode('ascii').say;
        say '/on-body ------------------------------';
    },
);
my $fh = open 't/http/body/dat/002-content.dat', :bin;
loop {
    my $buf = $fh.read(1024);
    if $buf.bytes == 0 {
        $parser.finish;
        last;
    }
    $parser.add($buf);
}
@headers.perl.say;

done-testing;

