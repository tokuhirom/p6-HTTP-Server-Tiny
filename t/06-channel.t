use v6;

use Test;
use lib 't/lib';
use Test::TCP;

use HTTP::Server::Tiny;
use HTTP::Tinyish;

plan 4;

my $port = 15555;

#my $server = HTTP::Server::Tiny.new(host => '127.0.0.1', port => $port);

my $channel = Channel.new;

#Testing promises
my $served-reply-ok = Promise.new;
my $filled-channel-ok = Promise.new;

# Thread.start({
#     $server.run(sub ($env) {
#         return start { 200, ['Content-Type' => 'text/plain'], $channel };
#     });
# }, :app_lifetime);

my $running-server = start {
  HTTP::Server::Tiny.new(host => '127.0.0.1', port => $port).run(sub ($env) {
      $served-reply-ok.keep(True);

      return start {200, ['Content-Type' => 'text/plain'], $channel};
  });

  CATCH { skip-rest "{ .Str }\n{ .backtrace }"; exit 1 }
}

my $channel-filler = start {
   for 1..100 {
     $channel.send($_.Str.encode('utf-8'));
   }
   $channel.close;

   $filled-channel-ok.keep(True);
}

my $test-request = Promise.in(1).then: {
  # Make request when port ready
  wait_port($port);
  my $resp = HTTP::Tinyish.new.post(
    "http://127.0.0.1:$port/",
     headers => {
          'content-type' => 'application/x-www-form-urlencoded'
      },
      content => 'foo=bar'
  );

  # Check reply
  is $resp<status>, 200, "Response status";
  is(
    $resp<content>,
    "123456789101112131415161718192021222324252627282930313233343536373839404142434445464748495051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899100",
    "Received channel content as response from post request"
  );
}

# Timeout test if longer than 5 seconds
await Promise.anyof(
  Promise.allof($test-request, $channel-filler),
  $running-server,
  Promise.in(5).then({ skip-rest "Test timed out!"; exit 1; })
);
# We will proceed if the channel filler completed and the test request is complete

# Check specific actions where executed
ok await($filled-channel-ok), "Channel was filled";
ok await($served-reply-ok), "Server executed reply";
