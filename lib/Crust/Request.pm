use v6;

unit class Crust::Request;

has $.env;

method new(Hash $env) {
    self.bless(env => $env);
}

method address()      { $.env<REMOTE_ADDR> }
method remote-host()  { $.env<REMOTE_HOST> }
method protocol()     { $.env<SERVER_PROTOCOL> }
method method()       { $.env<REQUEST_METHOD> }
method port()         { $.env<SERVER_PORT> }
method user()         { $.env<REMOTE_USER> }
method request_-ri()  { $.env<REQUEST_URI> }
method path-info()    { $.env<PATH_INFO> }
method path()         { $.env<PATH_INFO> || '/' }
method query-string() { $.env<QUERY_STRING> }
method script-name()  { $.env<SCRIPT_NAME> }
method scheme()       { $.env<psgi.url_scheme> }
method secure()       { $.scheme eq 'https' }
method body()         { $.env<psgi.input> }
method input()        { $.env<psgi.input> }

method content-length()   { $.env<CONTENT_LENGTH> }
method content-type()     { $.env<CONTENT_TYPE> }

method session()         { $.env<psgix.session> }
method session-options() { $.env<psgix.session.options> }
method logger()          { $.env<psgix.logger> }

# TODO: sub cookies {
# TODO: sub query_parameters {
# TODO: sub content {
# TODO: sub raw_body { $_[0]->content }
# TODO: sub headers {
# TODO: sub content_encoding { shift->headers->content_encoding(@_) }
# TODO: sub header           { shift->headers->header(@_) }
# TODO: sub referer          { shift->headers->referer(@_) }
# TODO: sub user_agent       { shift->headers->user_agent(@_) }
# TODO: sub body_parameters {
# TODO: sub parameters {
# TODO: sub uploads {
# TODO: sub param {
# TODO: sub upload {
# TODO: sub uri {
# TODO: sub base {
# TODO: sub new_response {

