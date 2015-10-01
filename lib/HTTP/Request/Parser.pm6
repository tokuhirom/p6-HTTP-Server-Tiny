use v6;

unit class HTTP::Request::Parser;

my Buf $http_header_end_marker = Buf.new(13, 10, 13, 10);

# >0: header size
# -1: failed
# -2: request is partial
sub parse-http-request(Blob $resp) is export {
    CATCH { default { say $_ } }

    my Int $header_end_pos = 0;
    while ( $header_end_pos < $resp.bytes ) {
        if ($http_header_end_marker eq $resp.subbuf($header_end_pos, 4)) {
            last;
        }
        $header_end_pos++;
    }

    if ($header_end_pos < $resp.bytes) {
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
            return -2,Nil;
        }

        for @header_lines {
            if $_ ~~ m/ ^^ ( <[ A..Z a..z - ]>+ ) \s* \: \s* (.+) $$ / {
                my ($k, $v) = @($/);
                $k = $k.subst(/\-/, '_', :g);
                $k = $k.uc;
                if $k ne 'CONTENT_LENGTH' && $k ne 'CONTENT_TYPE' {
                    $k = 'HTTP_' ~ $k;
                }
                $env{$k} = $v.Str;
            } else {
                die "invalid header: $_";
            }
        }

        return $header_end_pos+4, $env;
    } else {
        return -1,Nil;
    }
}

