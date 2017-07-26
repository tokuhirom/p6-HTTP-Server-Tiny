use v6;
use Test;
use HTTP::Tinyish;

plan 1;

# Try fetching an url before the time out!
await Promise.anyof(
  Promise.start({
    my $resp = HTTP::Tinyish.new.get("https://github.com/skaji/perl6-HTTP-Tinyish");
    unless is($resp<status>, 200, 'GET response code') {
      diag "Unable to reach github. Check your response code, if 599 you may be missing curl.";
    }
  }),
  Promise.in(5).then({ skip-rest "Test timed out!"; exit 1 })
);
