xquery version "1.0-ml";
(: Library module for URL rewrite.
 : It is cleaner to do everything here, so it can be tested.
 : This is controller code.
 :)
module namespace m="http://marklogic.com/rundmc/apidoc/rewrite";

declare default function namespace "http://www.w3.org/2005/xpath-functions";

import module namespace u="http://marklogic.com/rundmc/util"
  at "/lib/util-2.xqy";
import module namespace api="http://marklogic.com/rundmc/api"
  at "/apidoc/model/data-access.xqy";
import module namespace ml="http://developer.marklogic.com/site/internal"
  at "/model/data-access.xqy";
import module namespace srv="http://marklogic.com/rundmc/server-urls"
  at "/controller/server-urls.xqy";

declare namespace x="http://www.w3.org/1999/xhtml";

declare variable $DEBUG as xs:boolean? := xs:boolean(
  xdmp:get-request-field('debug')) ;

declare variable $ACCESS-PATHS := u:get-doc("/controller/access.xml")/paths ;

(: $PATH is just the original path, unless this is a REST doc, in which
 case we also might have to look at the query string (translating
 "?" to "@") :)
declare variable $PATH := (
  if (contains($PATH-ORIG, '/REST/') and $QUERY-STRING) then $REST-DOC-PATH
  else $PATH-ORIG ) ;

declare variable $PATH-ORIG := try {
  xdmp:url-decode(xdmp:get-request-path()) } catch ($ex) {
  xdmp:get-request-path() };

declare variable $PATH-PREFIX := (
  if ($VERSION-SPECIFIED) then concat("/", $VERSION-SPECIFIED, "/")
  else "/") ;
declare variable $PATH-PLUS-INDEX := concat(
  '/apidoc', $PATH, '/index.xml');
declare variable $PATH-TAIL := substring-after($PATH, $PATH-PREFIX) ;

declare variable $PATH-WITHOUT-VERSION := concat(
  '/', $PATH-TAIL) ;
declare variable $PATH-WITH-VERSION := concat(
  '/', $VERSION, $PATH-WITHOUT-VERSION) ;

declare variable $URL-ORIG := xdmp:get-request-url();
declare variable $QUERY-STRING := substring-after($URL-ORIG, '?');

declare variable $VERSION-SPECIFIED := (
  if (matches($PATH, '^/[0-9]\.[0-9]$')) then substring-after($PATH, '/')
  else if (matches($PATH, '^/[0-9]\.[0-9]/')) then substring-before(
    substring-after($PATH, '/'), '/')
  else "") ;

declare variable $VERSION := (
  if ($VERSION-SPECIFIED) then $VERSION-SPECIFIED
  else $api:default-version) ;

declare variable $VERSION-LATEST := '7.0' ;

declare variable $ROOT-DOC-URL := concat(
  '/apidoc/', $api:default-version, '/index.xml');
(: when version is unspecified in path :)
declare variable $DOC-URL-DEFAULT := concat(
  '/apidoc/', $api:default-version, $PATH, '.xml');
(: when version is specified in path :)
declare variable $DOC-URL := concat(
  '/apidoc', $PATH, '.xml');

(: For REST doc URIs, translate "?" to "@",
 : ignore trailing ampersands, and ignore unknown parameters.
 :)
declare variable $REST-DOC-PATH := (
  (: TODO sounds expensive. :)
  let $candidate-uris := (
    cts:uri-match(
      concat(
        '/apidoc/', $api:default-version, $PATH-ORIG,
        $api:REST-uri-questionmark-substitute, "*")),
    cts:uri-match(
      concat('/apidoc/',
        $PATH-ORIG, $api:REST-uri-questionmark-substitute, "*")))

  (: TODO use function mapping? :)
  let $known-query-params := distinct-values(
    for $uri in $candidate-uris
    return m:REST-doc-query-param($uri))[string(.)]

  let $canonicalized-query-string := string-join(
    for $name in xdmp:get-request-field-names()
    where $name = $known-query-params
    order by $name
    return (
      for $value in xdmp:get-request-field($name)
      return concat($name, '=', $value)
      , '&amp;'))
  return (
    if ($canonicalized-query-string)
    then concat(
      $PATH-ORIG,
      $api:REST-uri-questionmark-substitute,
      $canonicalized-query-string)
    else $PATH-ORIG))
;

declare variable $MATCHING-FUNCTIONS := ml:get-matching-functions(
  $PATH-TAIL, $api:version) ;

declare variable $MATCHING-FUNCTION-COUNT := count($MATCHING-FUNCTIONS) ;

declare variable $MESSAGE-PAT := (
  '^/guide/messages/([A-Z])+\-en/([A-Z]+-[A-Z]+)$') ;

declare function m:log(
  $label as xs:string,
  $list as xs:anyAtomicType*,
  $level as xs:string)
as empty-sequence()
{
  xdmp:log(text { '['||$label||']', $list }, $level)
};

declare function m:fine(
  $label as xs:string,
  $list as xs:anyAtomicType*)
as empty-sequence()
{
  m:log($label, $list, 'fine')
};

declare function m:debug(
  $label as xs:string,
  $list as xs:anyAtomicType*)
as empty-sequence()
{
  m:log($label, $list, 'debug')
};

declare function m:info(
  $label as xs:string,
  $list as xs:anyAtomicType*)
as empty-sequence()
{
  m:log($label, $list, 'info')
};

declare function m:warning(
  $label as xs:string,
  $list as xs:anyAtomicType*)
as empty-sequence()
{
  m:log($label, $list, 'warning')
};

declare function m:error(
  $code as xs:string,
  $items as item()*)
as empty-sequence()
{
  error((), 'REWRITE-'||$code, $items)
};

(: ASSUMPTION: each REST doc will have at most one query parameter in its URI :)
declare function m:REST-doc-query-param($doc-uri as xs:string)
  as xs:string
{
  substring-before(
    substring-after($doc-uri, $api:REST-uri-questionmark-substitute),
    '=')
};

(: Path to render a document using XSLT :)
declare function m:transform(
  $source-uri as xs:string,
  $path as xs:string)
as xs:string
{
  if (not($DEBUG)) then () else m:debug(
    'transform', ('source', $source-uri, 'path', $path)),
  concat(
    "/apidoc/controller/transform.xqy?src=", $source-uri,
    "&amp;version=", $VERSION-SPECIFIED,
    "&amp;", $QUERY-STRING,
    if ($path eq "") then () else "&amp;path=", $path)
};

declare function m:transform($source-uri as xs:string)
  as xs:string
{
  m:transform($source-uri, "")
};

(: Grab doc from database :)
declare function m:get-db-file($source-uri)
 as xs:string
{
  concat("/controller/get-db-file.xqy?uri=", $source-uri)
};

declare function m:function-url($function as document-node())
  as xs:string
{
  concat($PATH-PREFIX, $function/*/api:function[1]/@fullname)
};

declare function m:redirect($path as xs:string)
  as xs:string
{
  (: This is a temporary redirect: 302 not 301. :)
  concat(
    '/controller/redirect.xqy?path=',
    xdmp:url-encode($path))
};

declare function m:redirect-for-path($path as xs:string)
as xs:string
{
  (: This is a permanent redirect: 301 vs 302. :)
  xdmp:set-response-code(301, "Moved Permanently"),
  xdmp:add-response-header("Location", $path),
  m:redirect($path)
};

(: Redirect to the right place,
 : and rely on the page anchor matching the id.
 :)
declare function m:redirect-for-message(
  $path as xs:string,
  $id as xs:string)
as xs:string
{
  if (not($DEBUG)) then () else m:debug(
    'redirect-for-message', ('path', $path, 'id', $id)),
  m:redirect(
    concat(
      substring-before($path, '/'||$id),
      '#', $id))
};

declare function m:redirect-for-version($version as xs:string)
as xs:string
{
  m:redirect-for-path(substring-after($PATH, "/"||$version))
};

(: TODO figure out a way to break this up. :)
declare function m:rewrite()
  as xs:string
{
  if (not($DEBUG)) then () else m:debug(
    'rewrite',
    ('path', $PATH, 'path-prefix', $PATH-PREFIX, 'path-tail', $PATH-TAIL,
      'version', $VERSION)),

  (: SCENARIO 1: External redirect :)
  (: When the user hits Enter in the TOC filter box :)
  if ($PATH eq '/do-do-search') then m:redirect(
    concat($srv:search-page-url, "?", $QUERY-STRING))
  (: Externally redirect paths with trailing slashes :)
  else if (($PATH ne '/') and ends-with($PATH, '/')) then m:redirect(
    concat(
      substring($PATH, 1, string-length($PATH) - 1),
      if ($QUERY-STRING) then concat('&amp;', $QUERY-STRING) else ()))
  (: Redirect naked /guide and /javadoc to / :)
  else if ($PATH-TAIL = ("guide", "javadoc")) then m:redirect(
    $PATH-PREFIX)
  (: Redirect /dotnet to /dotnet/xcc :)
  else if ($PATH-TAIL eq "dotnet") then m:redirect(
    concat($PATH, '/xcc/index.html'))
  (: Redirect /cpp to /cpp/udf :)
  else if ($PATH-TAIL eq "cpp") then m:redirect(
    concat($PATH, '/udf/index.html'))
  (: Redirect path without index.html to index.html :)
  else if ($PATH-TAIL = ("javadoc/hadoop",
      "javadoc/client",
      "javadoc/xcc",
      "dotnet/xcc",
      "cpp/udf")) then m:redirect(
    concat($PATH, '/index.html'))

  (: Redirect requests for older versions 301 and go to latest :)
  else if (starts-with($PATH, "/4.2")) then m:redirect-for-version('4.2')
  else if (starts-with($PATH, "/4.1")) then m:redirect-for-version('4.1')
  else if (starts-with($PATH, "/4.0")) then m:redirect-for-version('4.0')
  else if (starts-with($PATH, "/3.2")) then m:redirect-for-version('3.2')
  else if (starts-with($PATH, "/3.1")) then m:redirect-for-version('3.1')

  (: SCENARIO 2: Internal rewrite :)

  (: SCENARIO 2A: Serve up the JavaScript-based docapp redirector :)
  else if (ends-with($PATH, "docapp.xqy"))
  then "/apidoc/controller/docapp-redirector.xqy"

  (: SCENARIO 2B: Serve content from file system :)
  (: Remove version from the URL for versioned assets :)
  else if (matches($PATH, '^/(css|images)/v-[0-9]*/.*')) then replace(
    $PATH, '/v-[0-9]*', '')

  (: If the path starts with one of the designated paths in the code base,
   : then serve from filesystem.
   :)
  else if ($ACCESS-PATHS/prefix[starts-with($PATH,.)]) then $PATH-ORIG

  (: SCENARIO 2C: Serve content from database :)
  (: Respond with DB contents for /media  :)
  else if (starts-with($PATH, '/media/')) then m:get-db-file($PATH)

  (: For zip file requests, we assume the zip file of all docs :)
  else if (ends-with($PATH, '.zip')) then m:get-db-file(
    concat("/apidoc", $PATH))

  (: Respond with DB contents for PDF and HTML docs :)
  else if (ends-with($PATH, '.pdf')
    or matches($PATH, '/(cpp|dotnet|javadoc)/')) then (
    let $file-uri := concat('/apidoc', $PATH-WITH-VERSION)
    return m:get-db-file($file-uri))

  (: redirect /package to /pkg because we changed the prefix :)
  else if ($PATH eq "/package") then m:redirect("/pkg")

  (: Transform /message/*-* for single page message reference.
   : This expects something like
   : /guide/messages/XDMP-en/XDMP-BAD
   : and we want to redirect to something like
   : /apidoc/7.0/guide/messages/XDMP-en.xml#XDMP-BAD
   :)
  else if (matches($PATH, $MESSAGE-PAT)) then m:redirect-for-message(
    $PATH-WITH-VERSION,
    replace($PATH, $MESSAGE-PAT, '$2'))

  (: Ignore URLs starting with "/private/" :)
  else if (starts-with($PATH, '/private/')) then "/controller/notfound.xqy"

  (: OK to expose xray like this? :)
  else if (starts-with($PATH, '/xray')) then $PATH-ORIG||'/index.xqy'

  (: Root request: "/" means "index.xml" inside the default version's directory :)
  else if ($PATH eq '/') then m:transform($ROOT-DOC-URL)

  (: If the version-specific doc path requested, e.g., /4.2/foo, is available,
   : then serve it
   :)
  else if (doc-available($DOC-URL)) then m:transform($DOC-URL)

  (: A version-specific root request, e.g., /4.2 :)
  else if ($PATH eq concat('/', $VERSION-SPECIFIED)
    and doc-available($PATH-PLUS-INDEX)) then m:transform($PATH-PLUS-INDEX)

  (: Otherwise, look in the default version directory :)
  else if (doc-available($DOC-URL-DEFAULT)) then m:transform($DOC-URL-DEFAULT)

  (: SCENARIO 3: External redirect to matching function page
   : If the path matches exactly one function's local name,
   then redirect to that page.
   :)
  else if ($MATCHING-FUNCTION-COUNT eq 1) then m:redirect(
    m:function-url($MATCHING-FUNCTIONS))

  (: If the path matches more than one function's local name,
   : show the first one.
   :)
  else if ($MATCHING-FUNCTION-COUNT gt 1) then m:redirect(
    concat(
      m:function-url($MATCHING-FUNCTIONS[1]),
      xdmp:url-encode("?show-alternatives=yes")))

  (: SCENARIO 4: Not found anywhere :)
  else (
    "/controller/notfound.xqy",
    xdmp:log(text { 'NOTFOUND', xdmp:url-decode($DOC-URL) }))
};

(: rewrite.xqm :)