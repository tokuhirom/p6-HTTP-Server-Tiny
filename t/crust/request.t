use v6;

use Test;
use Crust::Request;
use Hash::MultiValue;

my $req = Crust::Request.new({
    :REMOTE_ADDR<127.0.0.1>,
    :QUERY_STRING<foo=bar&foo=baz>
});
is $req.address, '127.0.0.1';
my $p = $req.query_paramerters;
ok [$p.all-pairs] eqv [:foo<bar>, :foo<baz>];

done-testing;
