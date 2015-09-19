use v6;

unit class Crust::Headers;

use Hash::MultiValue;

has $!env = Hash::MultiValue.new;

# $env is PSGI's env header.
method new(Hash $env) {
    self.bless()!initialize($env);
}

method !initialize(Hash $env) {
    for $env.kv -> $k, $v {
        self.header($k, $v);
    }
    self;
}

multi method header(Str $key) {
    return $!env{$key.lc};
}

multi method header(Str $key, $val) {
    unless $val.defined {
        die "undefined value in header value: $key";
    }
    $!env{$key.lc} = $val.Str;
}

method content-type() {
    self.header('content-type');
}

method content-length() {
    self.header('content-length');
}

method Str() {
    $!env.all-kv.map(-> $k, $v { "$k: $v" }).join("\n");
}

