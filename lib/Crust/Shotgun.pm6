use v6;

unit class Crust::Shotgun;

use JSON::Tiny;

sub make-shotgun-app(Str $appfile) is export {
    return sub ($env) {
        my @args = $*EXECUTABLE;
        @*INC ==> map { "-I$_" } ==> @args;
        @args.push("-e", 'use Crust::Shotgun; run-shotgun(@*ARGS[0])', $appfile);
        my $proc = run(|@args, :out);
        if $proc {
            my $json = $proc.out.slurp-rest;
            my $resp = from-json($json);
            return $resp;
        } else {
            die "cannot invoke psgi app($appfile): $proc";
        }
    }
}

sub run-shotgun(Str $appfile) is export {
    my $app = EVALFILE($appfile);
    if $app.isa(Sub) {
        my $resp = $app($env);
        say to-json($resp);
    } else {
        say to-json([500, [], ["psgi file must return Sub, but {{$app}}"]]);
    }
}
