//=====================================================================
// JSONPARSER_H - prototypes/constants for the hand-rolled JSON parser.
//
// Parses arbitrary JSON text into an in-memory node tree (jsonDoc_t).
// No external library, no Db2 SQL/JSON functions - pure RPG. Strings
// and numbers are kept as (start,len) spans into the original source
// text rather than copied into per-node buffers, so a node is a small
// fixed-size struct regardless of how long the underlying value is;
// jsonNodeGetString()/jsonNodeGetNumber() decode the span on demand.
//=====================================================================

dcl-c JSON_MAXDOC    1048576;   // max JSON document size handled (bytes)
dcl-c JSON_MAXVAL    32000;     // max length of a decoded scalar value
dcl-c JSON_MAXKEYLEN 256;       // max property name length
dcl-c JSON_MAXKEYS   256;       // max object properties enumerated at once
dcl-c JSON_MAXNODES  60000;     // max nodes (values+members) per document

dcl-c JSONTYPE_OBJECT  'object';
dcl-c JSONTYPE_ARRAY   'array';
dcl-c JSONTYPE_STRING  'string';
dcl-c JSONTYPE_NUMBER  'number';
dcl-c JSONTYPE_BOOLEAN 'boolean';
dcl-c JSONTYPE_NULL    'null';
dcl-c JSONTYPE_NONE    '';      // node index does not resolve to anything

// node index 0 always means "no node" (absent / not found / parse error)
dcl-c JSON_NONODE 0;

//---------------------------------------------------------------------
// jsonNode_t - one parsed JSON value. keyStart/keyLen are only
// meaningful when the node's parent is an object (the node's property
// name); valStart/valLen point at the raw source text of a string or
// number value (boolVal carries the value directly for booleans;
// object/array nodes use firstChild/nextSib/childCount instead).
//---------------------------------------------------------------------
dcl-ds jsonNode_t qualified template;
  kind       varchar(10);
  parent     int(10);
  firstChild int(10);
  lastChild  int(10);
  nextSib    int(10);
  childCount int(10);
  keyStart   int(10);
  keyLen     int(10);
  valStart   int(10);
  valLen     int(10);
  boolVal    ind;
end-ds;

//---------------------------------------------------------------------
// jsonDoc_t - a parsed document: the raw source text plus the node
// pool. rootIdx is the top-level value's node index (0 if parsing
// failed before any node was produced).
//---------------------------------------------------------------------
dcl-ds jsonDoc_t qualified template;
  text      varchar(JSON_MAXDOC:4) ccsid(*utf8);
  nodeCount int(10);
  rootIdx   int(10);
  ok        ind;
  errPos    int(10);
  errMsg    varchar(120);
  nodes     likeds(jsonNode_t) dim(JSON_MAXNODES);
end-ds;

dcl-ds jsonKeyList_t qualified template;
  count int(10);
  name  varchar(JSON_MAXKEYLEN) dim(JSON_MAXKEYS);
end-ds;

//---------------------------------------------------------------------
// jsonParse - parse JSON text into doc. Returns *on on success. On
// failure doc.ok is *off and doc.errPos/errMsg describe the problem;
// doc.rootIdx may still be JSON_NONODE.
//---------------------------------------------------------------------
dcl-pr jsonParse ind;
  text varchar(JSON_MAXDOC:4) const;
  doc  likeds(jsonDoc_t);
end-pr;

//---------------------------------------------------------------------
// Tree navigation / accessors. All take a parsed doc and a node index
// (JSON_NONODE/0 is always treated as "absent").
//---------------------------------------------------------------------
dcl-pr jsonNodeType varchar(10);
  doc     likeds(jsonDoc_t) const;
  nodeIdx int(10) const;
end-pr;

dcl-pr jsonNodeGetString varchar(JSON_MAXVAL);
  doc     likeds(jsonDoc_t) const;
  nodeIdx int(10) const;
end-pr;

dcl-pr jsonNodeGetNumber packed(31:10);
  doc     likeds(jsonDoc_t) const;
  nodeIdx int(10) const;
end-pr;

dcl-pr jsonNodeGetBool ind;
  doc     likeds(jsonDoc_t) const;
  nodeIdx int(10) const;
end-pr;

dcl-pr jsonNodeIsInteger ind;
  doc     likeds(jsonDoc_t) const;
  nodeIdx int(10) const;
end-pr;

dcl-pr jsonNodeKeyName varchar(JSON_MAXKEYLEN);
  doc     likeds(jsonDoc_t) const;
  nodeIdx int(10) const;
end-pr;

// number of elements in an array node (0 if not an array/absent)
dcl-pr jsonNodeArrayCount int(10);
  doc     likeds(jsonDoc_t) const;
  nodeIdx int(10) const;
end-pr;

// node index of the i'th (0-based) array element, JSON_NONODE if out of range
dcl-pr jsonNodeArrayItem int(10);
  doc     likeds(jsonDoc_t) const;
  nodeIdx int(10) const;
  i       int(10) const;
end-pr;

// node index of the object member named key, JSON_NONODE if absent/not an object
dcl-pr jsonNodeObjectGet int(10);
  doc     likeds(jsonDoc_t) const;
  nodeIdx int(10) const;
  key     varchar(JSON_MAXKEYLEN) const;
end-pr;

// does the object node have a member named key?
dcl-pr jsonNodeObjectHas ind;
  doc     likeds(jsonDoc_t) const;
  nodeIdx int(10) const;
  key     varchar(JSON_MAXKEYLEN) const;
end-pr;

// enumerate the member names of an object node (no-op / empty if not an object)
dcl-pr jsonNodeObjectKeys;
  doc     likeds(jsonDoc_t) const;
  nodeIdx int(10) const;
  keys    likeds(jsonKeyList_t);
end-pr;

// REGEXP_LIKE-backed pattern match, used for the schema "pattern" keyword
dcl-pr jsonRegexMatch ind;
  value   varchar(JSON_MAXVAL) const;
  pattern varchar(JSON_MAXVAL) const;
end-pr;
