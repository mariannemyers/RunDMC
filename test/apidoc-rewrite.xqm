xquery version "1.0-ml";
(: sample test module :)

(: TODO submit xray pull request to support xqm :)

module namespace t="http://github.com/robwhitby/xray/test";

declare default function namespace "http://www.w3.org/2005/xpath-functions";

import module namespace assert="http://github.com/robwhitby/xray/assertions"
  at "/xray/src/assertions.xqy";

import module namespace rw="http://marklogic.com/rundmc/apidoc/rewrite"
  at "/apidoc/controller/rewrite.xqm";

declare %t:case function t:message-XDMP-BAD()
{
  xdmp:set($rw:PATH-ORIG, '/guide/messages/XDMP-en/XDMP-BAD'),
  xdmp:set($rw:URL-ORIG, 'http://localhost:8011'||$rw:PATH-ORIG),
  assert:equal(
    rw:rewrite(),
    '/controller/redirect.xqy?path=/'
    ||$rw:VERSION-LATEST
    ||'/guide/messages/XDMP-en%23XDMP-BAD')
};

declare %t:case function t:root()
{
  xdmp:set($rw:PATH-ORIG, '/'),
  xdmp:set($rw:URL-ORIG, 'http://localhost:8011'||$rw:PATH-ORIG),
  assert:equal(
    rw:rewrite(),
    '/apidoc/controller/transform.xqy?src=/apidoc/'
    ||$rw:VERSION-LATEST
    ||'/index.xml&amp;version=&amp;')
};

(: test/apidoc-rewrite.xqm :)