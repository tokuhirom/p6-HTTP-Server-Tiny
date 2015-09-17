use v6;

unit module Test::Utils;

use NativeCall;

constant SIGTERM is export = 15;

sub kill(int $pid, int $sig)
    returns Int
    is native
    is export
    { ... }

sub fork()
    returns Int
    is native
    is export
    { ... }

module private {
    our sub waitpid(Int $pid, CArray[int] $status, Int $options)
            returns Int is native { ... }
}

sub waitpid(Int $pid, Int $options) is export {
    my $status = CArray[int].new;
    $status[0] = 0;
    my $ret_pid = private::waitpid($pid, $status, $options);
    return ($ret_pid, $status[0]);
}

