**free
//=====================================================================
// JSONSCHEMA - recursive-descent JSON Schema validator (core subset).
// Walks the schema document; for every keyword present, checks the
// corresponding part of the data document via jsonutil's generic
// JSON access procedures. See jsonschema_h.rpgle for keyword coverage.
//=====================================================================
ctl-opt nomain;

/copy 'src/copy/jsonschema_h.rpgle'

dcl-s gSchemaDoc varchar(JSON_MAXDOC:4) ccsid(*utf8) static;
dcl-s gDataDoc   varchar(JSON_MAXDOC:4) ccsid(*utf8) static;
dcl-ds gResult likeds(jsResult_t) static;

//---------------------------------------------------------------------
// forward prototypes (mutual/recursive calls within this module)
//---------------------------------------------------------------------
dcl-pr jsValidateNode ind;
  schemaPath varchar(JSON_MAXPATH) const;
  dataPath   varchar(JSON_MAXPATH) const;
  errPath    varchar(JS_MAXPATH) const;
end-pr;

dcl-pr jsAddError;
  errPath varchar(JS_MAXPATH) const;
  message varchar(JS_MAXMSG) const;
end-pr;

dcl-pr jsCheckType ind;
  schemaPath varchar(JSON_MAXPATH) const;
  dataPath   varchar(JSON_MAXPATH) const;
  errPath    varchar(JS_MAXPATH) const;
end-pr;

dcl-pr jsTypeMatches ind;
  expected varchar(20) const;
  actual   varchar(10) const;
  dataPath varchar(JSON_MAXPATH) const;
end-pr;

dcl-pr jsCheckEnum ind;
  schemaPath varchar(JSON_MAXPATH) const;
  dataPath   varchar(JSON_MAXPATH) const;
  errPath    varchar(JS_MAXPATH) const;
end-pr;

dcl-pr jsCheckStringConstraints ind;
  schemaPath varchar(JSON_MAXPATH) const;
  dataPath   varchar(JSON_MAXPATH) const;
  errPath    varchar(JS_MAXPATH) const;
end-pr;

dcl-pr jsCheckNumberConstraints ind;
  schemaPath varchar(JSON_MAXPATH) const;
  dataPath   varchar(JSON_MAXPATH) const;
  errPath    varchar(JS_MAXPATH) const;
end-pr;

dcl-pr jsCheckArrayConstraints ind;
  schemaPath varchar(JSON_MAXPATH) const;
  dataPath   varchar(JSON_MAXPATH) const;
  errPath    varchar(JS_MAXPATH) const;
end-pr;

dcl-pr jsCheckRequired ind;
  schemaPath varchar(JSON_MAXPATH) const;
  dataPath   varchar(JSON_MAXPATH) const;
  errPath    varchar(JS_MAXPATH) const;
end-pr;

dcl-pr jsCheckProperties ind;
  schemaPath varchar(JSON_MAXPATH) const;
  dataPath   varchar(JSON_MAXPATH) const;
  errPath    varchar(JS_MAXPATH) const;
end-pr;

dcl-pr jsCheckItems ind;
  schemaPath varchar(JSON_MAXPATH) const;
  dataPath   varchar(JSON_MAXPATH) const;
  errPath    varchar(JS_MAXPATH) const;
end-pr;

//=====================================================================
dcl-proc jsonSchemaValidate export;
  dcl-pi *n ind;
    schemaDoc varchar(JSON_MAXDOC:4) const;
    dataDoc   varchar(JSON_MAXDOC:4) const;
    result    likeds(jsResult_t);
  end-pi;

  gSchemaDoc       = schemaDoc;
  gDataDoc         = dataDoc;
  gResult.errCount = 0;

  jsValidateNode(JSON_ROOT : JSON_ROOT : '$');

  gResult.valid = (gResult.errCount = 0);
  result = gResult;
  return result.valid;
end-proc;

//---------------------------------------------------------------------
dcl-proc jsAddError;
  dcl-pi *n;
    errPath varchar(JS_MAXPATH) const;
    message varchar(JS_MAXMSG) const;
  end-pi;

  if gResult.errCount < JS_MAXERRORS;
    gResult.errCount += 1;
    gResult.errors(gResult.errCount).instancePath = errPath;
    gResult.errors(gResult.errCount).message      = message;
  endif;
end-proc;

//---------------------------------------------------------------------
// jsValidateNode - validate the value at dataPath against the
// (sub)schema at schemaPath. Caller guarantees dataPath exists;
// JSON Schema's "properties"/"items" only validate values that are
// actually present, so absence is handled by the caller (required
// for missing properties, simply not iterating absent array slots).
//---------------------------------------------------------------------
dcl-proc jsValidateNode;
  dcl-pi *n ind;
    schemaPath varchar(JSON_MAXPATH) const;
    dataPath   varchar(JSON_MAXPATH) const;
    errPath    varchar(JS_MAXPATH) const;
  end-pi;

  dcl-s errsBefore int(10);

  errsBefore = gResult.errCount;

  jsCheckType(schemaPath : dataPath : errPath);
  jsCheckEnum(schemaPath : dataPath : errPath);
  jsCheckStringConstraints(schemaPath : dataPath : errPath);
  jsCheckNumberConstraints(schemaPath : dataPath : errPath);
  jsCheckArrayConstraints(schemaPath : dataPath : errPath);
  jsCheckRequired(schemaPath : dataPath : errPath);
  jsCheckProperties(schemaPath : dataPath : errPath);
  jsCheckItems(schemaPath : dataPath : errPath);

  return (gResult.errCount = errsBefore);
end-proc;

//---------------------------------------------------------------------
// "type": a string, or an array of acceptable type strings.
//---------------------------------------------------------------------
dcl-proc jsCheckType;
  dcl-pi *n ind;
    schemaPath varchar(JSON_MAXPATH) const;
    dataPath   varchar(JSON_MAXPATH) const;
    errPath    varchar(JS_MAXPATH) const;
  end-pi;

  dcl-s typePath varchar(JSON_MAXPATH);
  dcl-s actual   varchar(10);
  dcl-s expected varchar(20);
  dcl-s list     varchar(200);
  dcl-s any      ind;
  dcl-s i        int(10);
  dcl-s n        int(10);

  typePath = jsonPathSeg(schemaPath:'type');

  if not jsonExists(gSchemaDoc:typePath);
    return *on;     // no "type" constraint
  endif;

  actual = jsonType(gDataDoc:dataPath);

  if jsonType(gSchemaDoc:typePath) = JSONTYPE_ARRAY;
    n    = jsonArrayCount(gSchemaDoc:typePath);
    any  = *off;
    list = '';
    for i = 0 to n - 1;
      expected = jsonGetString(gSchemaDoc:jsonPathIdx(typePath:i));
      if jsTypeMatches(expected:actual:dataPath);
        any = *on;
      endif;
      list = %trimr(list) + ' ' + %trim(expected);
    endfor;
    if not any;
      jsAddError(errPath : 'must be one of type [' + %trim(list)
                            + '] but found ' + %trim(actual));
      return *off;
    endif;
  else;
    expected = jsonGetString(gSchemaDoc:typePath);
    if not jsTypeMatches(expected:actual:dataPath);
      jsAddError(errPath : 'must be of type ' + %trim(expected)
                            + ' but found ' + %trim(actual));
      return *off;
    endif;
  endif;

  return *on;
end-proc;

dcl-proc jsTypeMatches;
  dcl-pi *n ind;
    expected varchar(20) const;
    actual   varchar(10) const;
    dataPath varchar(JSON_MAXPATH) const;
  end-pi;

  if %trim(expected) = 'integer';
    return (actual = JSONTYPE_NUMBER and jsonIsIntegerValue(gDataDoc:dataPath));
  endif;

  return (%trim(expected) = %trim(actual));
end-proc;

//---------------------------------------------------------------------
// "enum": value must equal one of a list of scalar literals.
// (Object/array enum members are not supported in the core subset.)
//---------------------------------------------------------------------
dcl-proc jsCheckEnum;
  dcl-pi *n ind;
    schemaPath varchar(JSON_MAXPATH) const;
    dataPath   varchar(JSON_MAXPATH) const;
    errPath    varchar(JS_MAXPATH) const;
  end-pi;

  dcl-s enumPath   varchar(JSON_MAXPATH);
  dcl-s candPath   varchar(JSON_MAXPATH);
  dcl-s actualType varchar(10);
  dcl-s candType   varchar(10);
  dcl-s found      ind;
  dcl-s i int(10);
  dcl-s n int(10);

  enumPath = jsonPathSeg(schemaPath:'enum');

  if not jsonExists(gSchemaDoc:enumPath);
    return *on;
  endif;

  n          = jsonArrayCount(gSchemaDoc:enumPath);
  actualType = jsonType(gDataDoc:dataPath);
  found      = *off;

  for i = 0 to n - 1;
    candPath = jsonPathIdx(enumPath:i);
    candType = jsonType(gSchemaDoc:candPath);
    if candType = actualType;
      select;
        when actualType = JSONTYPE_STRING or actualType = JSONTYPE_BOOLEAN;
          if jsonGetString(gSchemaDoc:candPath) = jsonGetString(gDataDoc:dataPath);
            found = *on;
          endif;
        when actualType = JSONTYPE_NUMBER;
          if jsonGetNumber(gSchemaDoc:candPath) = jsonGetNumber(gDataDoc:dataPath);
            found = *on;
          endif;
        when actualType = JSONTYPE_NULL;
          found = *on;
        other;
          // enum of object/array values not supported in core subset
      endsl;
    endif;
    if found;
      leave;
    endif;
  endfor;

  if not found;
    jsAddError(errPath : 'must match one of the values in enum');
    return *off;
  endif;
  return *on;
end-proc;

//---------------------------------------------------------------------
// "minLength" / "maxLength" / "pattern" - only meaningful for strings.
//---------------------------------------------------------------------
dcl-proc jsCheckStringConstraints;
  dcl-pi *n ind;
    schemaPath varchar(JSON_MAXPATH) const;
    dataPath   varchar(JSON_MAXPATH) const;
    errPath    varchar(JS_MAXPATH) const;
  end-pi;

  dcl-s ok      ind;
  dcl-s sval    varchar(JSON_MAXVAL);
  dcl-s slen    int(10);
  dcl-s bound   int(10);
  dcl-s pattern varchar(JSON_MAXVAL);

  if jsonType(gDataDoc:dataPath) <> JSONTYPE_STRING;
    return *on;
  endif;

  ok   = *on;
  sval = jsonGetString(gDataDoc:dataPath);
  slen = %len(sval);

  if jsonExists(gSchemaDoc:jsonPathSeg(schemaPath:'minLength'));
    bound = %int(jsonGetNumber(gSchemaDoc:jsonPathSeg(schemaPath:'minLength')));
    if slen < bound;
      jsAddError(errPath : 'length must be >= ' + %char(bound));
      ok = *off;
    endif;
  endif;

  if jsonExists(gSchemaDoc:jsonPathSeg(schemaPath:'maxLength'));
    bound = %int(jsonGetNumber(gSchemaDoc:jsonPathSeg(schemaPath:'maxLength')));
    if slen > bound;
      jsAddError(errPath : 'length must be <= ' + %char(bound));
      ok = *off;
    endif;
  endif;

  if jsonExists(gSchemaDoc:jsonPathSeg(schemaPath:'pattern'));
    pattern = jsonGetString(gSchemaDoc:jsonPathSeg(schemaPath:'pattern'));
    if not jsonRegexMatch(sval:pattern);
      jsAddError(errPath : 'must match pattern ' + %trim(pattern));
      ok = *off;
    endif;
  endif;

  return ok;
end-proc;

//---------------------------------------------------------------------
// "minimum" / "maximum" - only meaningful for numbers.
//---------------------------------------------------------------------
dcl-proc jsCheckNumberConstraints;
  dcl-pi *n ind;
    schemaPath varchar(JSON_MAXPATH) const;
    dataPath   varchar(JSON_MAXPATH) const;
    errPath    varchar(JS_MAXPATH) const;
  end-pi;

  dcl-s ok    ind;
  dcl-s nval  packed(31:10);
  dcl-s bound packed(31:10);

  if jsonType(gDataDoc:dataPath) <> JSONTYPE_NUMBER;
    return *on;
  endif;

  ok   = *on;
  nval = jsonGetNumber(gDataDoc:dataPath);

  if jsonExists(gSchemaDoc:jsonPathSeg(schemaPath:'minimum'));
    bound = jsonGetNumber(gSchemaDoc:jsonPathSeg(schemaPath:'minimum'));
    if nval < bound;
      jsAddError(errPath : 'must be >= ' + %trim(%char(bound)));
      ok = *off;
    endif;
  endif;

  if jsonExists(gSchemaDoc:jsonPathSeg(schemaPath:'maximum'));
    bound = jsonGetNumber(gSchemaDoc:jsonPathSeg(schemaPath:'maximum'));
    if nval > bound;
      jsAddError(errPath : 'must be <= ' + %trim(%char(bound)));
      ok = *off;
    endif;
  endif;

  return ok;
end-proc;

//---------------------------------------------------------------------
// "minItems" / "maxItems" - only meaningful for arrays.
//---------------------------------------------------------------------
dcl-proc jsCheckArrayConstraints;
  dcl-pi *n ind;
    schemaPath varchar(JSON_MAXPATH) const;
    dataPath   varchar(JSON_MAXPATH) const;
    errPath    varchar(JS_MAXPATH) const;
  end-pi;

  dcl-s ok    ind;
  dcl-s cnt   int(10);
  dcl-s bound int(10);

  if jsonType(gDataDoc:dataPath) <> JSONTYPE_ARRAY;
    return *on;
  endif;

  ok  = *on;
  cnt = jsonArrayCount(gDataDoc:dataPath);

  if jsonExists(gSchemaDoc:jsonPathSeg(schemaPath:'minItems'));
    bound = %int(jsonGetNumber(gSchemaDoc:jsonPathSeg(schemaPath:'minItems')));
    if cnt < bound;
      jsAddError(errPath : 'must contain >= ' + %char(bound) + ' items');
      ok = *off;
    endif;
  endif;

  if jsonExists(gSchemaDoc:jsonPathSeg(schemaPath:'maxItems'));
    bound = %int(jsonGetNumber(gSchemaDoc:jsonPathSeg(schemaPath:'maxItems')));
    if cnt > bound;
      jsAddError(errPath : 'must contain <= ' + %char(bound) + ' items');
      ok = *off;
    endif;
  endif;

  return ok;
end-proc;

//---------------------------------------------------------------------
// "required": array of property names that must be present.
//---------------------------------------------------------------------
dcl-proc jsCheckRequired;
  dcl-pi *n ind;
    schemaPath varchar(JSON_MAXPATH) const;
    dataPath   varchar(JSON_MAXPATH) const;
    errPath    varchar(JS_MAXPATH) const;
  end-pi;

  dcl-s reqPath varchar(JSON_MAXPATH);
  dcl-s name    varchar(JSON_MAXKEYLEN);
  dcl-s ok      ind;
  dcl-s i int(10);
  dcl-s n int(10);

  reqPath = jsonPathSeg(schemaPath:'required');

  if not jsonExists(gSchemaDoc:reqPath);
    return *on;
  endif;

  if jsonType(gDataDoc:dataPath) <> JSONTYPE_OBJECT;
    return *on;    // "required" only meaningful for objects
  endif;

  ok = *on;
  n  = jsonArrayCount(gSchemaDoc:reqPath);

  for i = 0 to n - 1;
    name = jsonGetString(gSchemaDoc:jsonPathIdx(reqPath:i));
    if not jsonExists(gDataDoc:jsonPathSeg(dataPath:name));
      jsAddError(errPath : 'missing required property "' + %trim(name) + '"');
      ok = *off;
    endif;
  endfor;

  return ok;
end-proc;

//---------------------------------------------------------------------
// "properties": recursively validate every defined property that is
// actually present in the instance (JSON Schema semantics: absent
// optional properties are simply not checked here).
//---------------------------------------------------------------------
dcl-proc jsCheckProperties;
  dcl-pi *n ind;
    schemaPath varchar(JSON_MAXPATH) const;
    dataPath   varchar(JSON_MAXPATH) const;
    errPath    varchar(JS_MAXPATH) const;
  end-pi;

  dcl-s propsPath varchar(JSON_MAXPATH);
  dcl-ds keys likeds(jsonKeyList_t);
  dcl-s ok ind;
  dcl-s childDataPath   varchar(JSON_MAXPATH);
  dcl-s childSchemaPath varchar(JSON_MAXPATH);
  dcl-s childErrPath    varchar(JS_MAXPATH);
  dcl-s i int(10);

  propsPath = jsonPathSeg(schemaPath:'properties');

  if not jsonExists(gSchemaDoc:propsPath);
    return *on;
  endif;

  if jsonType(gDataDoc:dataPath) <> JSONTYPE_OBJECT;
    return *on;    // "properties" only meaningful for objects
  endif;

  ok = *on;
  jsonObjectKeys(gSchemaDoc:propsPath:keys);

  for i = 1 to keys.count;
    childDataPath = jsonPathSeg(dataPath:keys.name(i));
    if jsonExists(gDataDoc:childDataPath);
      childSchemaPath = jsonPathSeg(propsPath:keys.name(i));
      childErrPath    = %trimr(errPath) + '.' + %trim(keys.name(i));
      if not jsValidateNode(childSchemaPath:childDataPath:childErrPath);
        ok = *off;
      endif;
    endif;
  endfor;

  return ok;
end-proc;

//---------------------------------------------------------------------
// "items": recursively validate every element of the instance array
// against the same sub-schema.
//---------------------------------------------------------------------
dcl-proc jsCheckItems;
  dcl-pi *n ind;
    schemaPath varchar(JSON_MAXPATH) const;
    dataPath   varchar(JSON_MAXPATH) const;
    errPath    varchar(JS_MAXPATH) const;
  end-pi;

  dcl-s itemsPath   varchar(JSON_MAXPATH);
  dcl-s childErrPath varchar(JS_MAXPATH);
  dcl-s ok ind;
  dcl-s i int(10);
  dcl-s n int(10);

  itemsPath = jsonPathSeg(schemaPath:'items');

  if not jsonExists(gSchemaDoc:itemsPath);
    return *on;
  endif;

  if jsonType(gDataDoc:dataPath) <> JSONTYPE_ARRAY;
    return *on;    // "items" only meaningful for arrays
  endif;

  ok = *on;
  n  = jsonArrayCount(gDataDoc:dataPath);

  for i = 0 to n - 1;
    childErrPath = %trimr(errPath) + '[' + %char(i) + ']';
    if not jsValidateNode(itemsPath:jsonPathIdx(dataPath:i):childErrPath);
      ok = *off;
    endif;
  endfor;

  return ok;
end-proc;
