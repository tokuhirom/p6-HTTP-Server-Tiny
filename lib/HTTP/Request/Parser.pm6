use v6;

unit class HTTP::Request::Parser;

my Buf $http_header_end_marker = Buf.new(13, 10, 13, 10);

constant DEBUGGING = %*ENV<REQUEST_PARSER_DEBUGGING>.Bool;

macro debug($message) {
    if DEBUGGING {
        quasi {
            say "[DEBUG] [{$*THREAD.id}] " ~ {{{$message}}};
        }
    } else {
        quasi { }
    }
}

sub parse-http-request(Blob $resp) is export {
    debug 'parsing http header';

    CATCH { default { say $_ } }

    my Int $header_end_pos = 0;
    while ( $header_end_pos < $resp.bytes ) {
        debug("subbuf");
        if ($http_header_end_marker eq $resp.subbuf($header_end_pos, 4)) {
            debug("found!");
            last;
        }
        debug("header_end_pos: $header_end_pos bytes:{$resp.bytes}");
        $header_end_pos++;
    }
    debug("finished header position searching");

    if ($header_end_pos < $resp.bytes) {
        debug("header received");
        my @header_lines = $resp.subbuf(
            0, $header_end_pos
        ).decode('ascii').split(/\r\n/);

        my $env = { };

        my Str $status_line = @header_lines.shift;
        if $status_line ~~ m/^(<[A..Z]>+)\s(\S+)\sHTTP\/1\.(.)$/ {
            $env<REQUEST_METHOD> = $/[0].Str;
            my $path_query = $/[1];
            if $path_query ~~ m/^ (.*?) [ \? (.*) ]? $/ {
                $env<PATH_INFO> = $/[0].Str;
                if $/[1].defined {
                    $env<QUERY_STRING> = $/[1].Str;
                } else {
                    $env<QUERY_STRING> = '';
                }
            }
        } else {
            die "cannot parse http request: $status_line";
        }

        for @header_lines {
            if $_ ~~ m/ ^^ ( <[ A..Z a..z - ]>+ ) \s* \: \s* (.+) $$ / {
                my ($k, $v) = @($/);
                $k = $k.subst(/\-/, '_', :g);
                $k = $k.uc;
                if $k ne 'CONTENT_LENGTH' {
                    $k = 'HTTP_' ~ $k;
                }
                $env{$k} = $v.Str;
            } else {
                die "invalid header: $_";
            }
        }

        return (True, $env, $header_end_pos+4);
    } else {
        debug("no header ending");
    }

    return (False, );
}

