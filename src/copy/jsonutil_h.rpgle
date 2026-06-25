//=====================================================================
// JSONUTIL_H - prototypes/constants for the JSON utility module.
//
// Generic, schema-agnostic access to arbitrary JSON text, built
// entirely on Db2 for i's native SQL/JSON support (JSON_EXISTS,
// JSON_VALUE, JSON_QUERY, JSON_TABLE, REGEXP_LIKE). No external
// library/service program dependency - everything here ships with
// the base OS (IBM i 7.3 and later).
//
// Paths use SQL/JSON path syntax, e.g.:  lax $."order-id".items[2]
// Build them with jsonPathSeg()/jsonPathIdx() rather than
// concatenating strings by hand, so property names are escaped
// correctly.
//=====================================================================

dcl-c JSON_MAXDOC    1048576;   // max JSON document size handled (bytes)
dcl-c JSON_MAXPATH   1024;      // max SQL/JSON path expression length
dcl-c JSON_MAXVAL    32000;     // max length of an extracted scalar value
dcl-c JSON_MAXKEYS   256;       // max object properties enumerated at once
dcl-c JSON_MAXKEYLEN 256;       // max property name length
dcl-c JSON_ROOT      'lax $';   // root of every SQL/JSON path

dcl-c JSONTYPE_OBJECT  'object';
dcl-c JSONTYPE_ARRAY   'array';
dcl-c JSONTYPE_STRING  'string';
dcl-c JSONTYPE_NUMBER  'number';
dcl-c JSONTYPE_BOOLEAN 'boolean';
dcl-c JSONTYPE_NULL    'null';
dcl-c JSONTYPE_NONE    '';      // path does not resolve to anything

dcl-ds jsonKeyList_t qualified template;
  count int(10);
  name  varchar(JSON_MAXKEYLEN) dim(JSON_MAXKEYS);
end-ds;

//---------------------------------------------------------------------
// jsonExists - does the given path resolve to a value in doc?
//---------------------------------------------------------------------
dcl-pr jsonExists ind;
  doc  varchar(JSON_MAXDOC:4) const;
  path varchar(JSON_MAXPATH) const;
end-pr;

//---------------------------------------------------------------------
// jsonType - JSON type of the value at path, or JSONTYPE_NONE if the
// path does not resolve to anything. Distinguishes string/number/
// boolean/null even though JSON_VALUE alone cannot (see jsonutil.sqlrpgle).
//---------------------------------------------------------------------
dcl-pr jsonType varchar(10);
  doc  varchar(JSON_MAXDOC:4) const;
  path varchar(JSON_MAXPATH) const;
end-pr;

//---------------------------------------------------------------------
// jsonGetString - scalar value at path, as text. Caller should only
// rely on this when jsonType() is string/number/boolean.
//---------------------------------------------------------------------
dcl-pr jsonGetString varchar(JSON_MAXVAL);
  doc  varchar(JSON_MAXDOC:4) const;
  path varchar(JSON_MAXPATH) const;
end-pr;

//---------------------------------------------------------------------
// jsonGetNumber - numeric value at path.
//---------------------------------------------------------------------
dcl-pr jsonGetNumber packed(31:10);
  doc  varchar(JSON_MAXDOC:4) const;
  path varchar(JSON_MAXPATH) const;
end-pr;

//---------------------------------------------------------------------
// jsonIsIntegerValue - true if the numeric value at path has no
// fractional part (used to distinguish "integer" from "number").
//---------------------------------------------------------------------
dcl-pr jsonIsIntegerValue ind;
  doc  varchar(JSON_MAXDOC:4) const;
  path varchar(JSON_MAXPATH) const;
end-pr;

//---------------------------------------------------------------------
// jsonArrayCount - number of elements in the array at path.
//---------------------------------------------------------------------
dcl-pr jsonArrayCount int(10);
  doc  varchar(JSON_MAXDOC:4) const;
  path varchar(JSON_MAXPATH) const;
end-pr;

//---------------------------------------------------------------------
// jsonObjectKeys - enumerate the top-level property names of the
// object at path. SQL/JSON path syntax has no wildcard for object
// member names, so this walks the raw JSON text returned by
// JSON_QUERY instead (see jsonutil.sqlrpgle for details).
//---------------------------------------------------------------------
dcl-pr jsonObjectKeys;
  doc  varchar(JSON_MAXDOC:4) const;
  path varchar(JSON_MAXPATH) const;
  keys likeds(jsonKeyList_t);
end-pr;

//---------------------------------------------------------------------
// jsonRegexMatch - does value match pattern (via SQL REGEXP_LIKE)?
//---------------------------------------------------------------------
dcl-pr jsonRegexMatch ind;
  value   varchar(JSON_MAXVAL) const;
  pattern varchar(JSON_MAXVAL) const;
end-pr;

//---------------------------------------------------------------------
// jsonPathSeg / jsonPathIdx - build a child path under parentPath,
// quoting/escaping property names correctly.
//---------------------------------------------------------------------
dcl-pr jsonPathSeg varchar(JSON_MAXPATH);
  parentPath varchar(JSON_MAXPATH) const;
  key        varchar(JSON_MAXKEYLEN) const;
end-pr;

dcl-pr jsonPathIdx varchar(JSON_MAXPATH);
  parentPath varchar(JSON_MAXPATH) const;
  idx        int(10) const;
end-pr;
