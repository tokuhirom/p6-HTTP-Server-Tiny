use v6;
use Test;
use HTTP::Tinyish;

plan 1;

# HTTP::Tinyish doesn't currently have any tests being run by zef installs.
# This leads to users installing all dependancies OK but then failing module install due to HTTP::Server::Tiny's tests failing.
# The situation makes it difficult to debug for edn users.
#
# This seems to commonly happen when curl is not in the environment path (giving a 599 error).
#
# Try fetching an url before the time out!
await Promise.anyof(
  Promise.start({
    my $resp = HTTP::Tinyish.new.get("https://github.com/skaji/perl6-HTTP-Tinyish");
    unless is($resp<status>, 200, 'GET response code') {
      diag "Unable to reach github. Check your response code, HTTP::Tinyish may not be fucntioning correctly!";
    }
  }),
  Promise.in(5).then({ skip-rest "Test timed out!"; exit 1 })
);
