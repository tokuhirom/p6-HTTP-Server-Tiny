use v6;

unit module Test::Utils;

use NativeCall;


sub fork()
    returns Int
    is native
    is export
    { ... }

module private {
    our sub waitpid(Int $pid, CArray[int] $status, Int $options)
            returns Int is native { ... }
    our sub kill(int $pid, int $sig)
        returns Int
        is native
        is export
        { ... }
}

sub waitpid(Int $pid, Int $options) is export {
    my $status = CArray[int].new;
    $status[0] = 0;
    my $ret_pid = private::waitpid($pid, $status, $options);
    return ($ret_pid, $status[0]);
}

sub kill(int $pid, Signal $sig) {
    return private::kill($pid, $sig.Int);
}
