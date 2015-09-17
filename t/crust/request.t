use v6;

use Test;
use Crust::Request;

my $req = Crust::Request.new({
    :REMOTE_ADDR<127.0.0.1>
});
is $req.address, '127.0.0.1';
