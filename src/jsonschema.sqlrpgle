**free
//=====================================================================
// JSONSCHEMA - recursive-descent JSON Schema validator (core subset).
//
// Both documents are parsed once, up front, by the hand-rolled parser
// in jsonparser.sqlrpgle into in-memory node trees; validation walks
// schema nodes against data nodes directly (no re-parsing per access,
// unlike a path-string-based approach).
//=====================================================================
ctl-opt nomain;

/copy 'src/copy/jsonschema_h.rpgle'

dcl-ds gSchema likeds(jsonDoc_t) static;
dcl-ds gData   likeds(jsonDoc_t) static;
dcl-ds gResult likeds(jsResult_t) static;

//---------------------------------------------------------------------
// forward prototypes (mutual/recursive calls within this module)
//---------------------------------------------------------------------
dcl-pr jsValidateNode ind;
  schemaIdx int(10) const;
  dataIdx   int(10) const;
  errPath   varchar(JS_MAXPATH) const;
end-pr;

dcl-pr jsAddError;
  errPath varchar(JS_MAXPATH) const;
  message varchar(JS_MAXMSG) const;
end-pr;

dcl-pr jsCheckType ind;
  schemaIdx int(10) const;
  dataIdx   int(10) const;
  errPath   varchar(JS_MAXPATH) const;
end-pr;

dcl-pr jsTypeMatches ind;
  expected varchar(20) const;
  actual   varchar(10) const;
  dataIdx  int(10) const;
end-pr;

dcl-pr jsCheckEnum ind;
  schemaIdx int(10) const;
  dataIdx   int(10) const;
  errPath   varchar(JS_MAXPATH) const;
end-pr;

dcl-pr jsCheckStringConstraints ind;
  schemaIdx int(10) const;
  dataIdx   int(10) const;
  errPath   varchar(JS_MAXPATH) const;
end-pr;

dcl-pr jsCheckNumberConstraints ind;
  schemaIdx int(10) const;
  dataIdx   int(10) const;
  errPath   varchar(JS_MAXPATH) const;
end-pr;

dcl-pr jsCheckArrayConstraints ind;
  schemaIdx int(10) const;
  dataIdx   int(10) const;
  errPath   varchar(JS_MAXPATH) const;
end-pr;

dcl-pr jsCheckRequired ind;
  schemaIdx int(10) const;
  dataIdx   int(10) const;
  errPath   varchar(JS_MAXPATH) const;
end-pr;

dcl-pr jsCheckProperties ind;
  schemaIdx int(10) const;
  dataIdx   int(10) const;
  errPath   varchar(JS_MAXPATH) const;
end-pr;

dcl-pr jsCheckItems ind;
  schemaIdx int(10) const;
  dataIdx   int(10) const;
  errPath   varchar(JS_MAXPATH) const;
end-pr;

//=====================================================================
dcl-proc jsonSchemaValidate export;
  dcl-pi *n ind;
    schemaDoc varchar(JSON_MAXDOC:4) const;
    dataDoc   varchar(JSON_MAXDOC:4) const;
    result    likeds(jsResult_t);
  end-pi;

  gResult.errCount = 0;

  if not jsonParse(schemaDoc:gSchema);
    jsAddError('$' : 'schema is not valid JSON: ' + %trim(gSchema.errMsg));
    gResult.valid = *off;
    result = gResult;
    return result.valid;
  endif;

  if not jsonParse(dataDoc:gData);
    jsAddError('$' : 'data is not valid JSON: ' + %trim(gData.errMsg));
    gResult.valid = *off;
    result = gResult;
    return result.valid;
  endif;

  jsValidateNode(gSchema.rootIdx : gData.rootIdx : '$');

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
// jsValidateNode - validate the data node against the schema node.
// Caller guarantees dataIdx exists; "properties"/"items" only
// validate values that are actually present, so absence is handled
// by the caller (required for missing properties, simply not
// iterating absent array slots).
//---------------------------------------------------------------------
dcl-proc jsValidateNode;
  dcl-pi *n ind;
    schemaIdx int(10) const;
    dataIdx   int(10) const;
    errPath   varchar(JS_MAXPATH) const;
  end-pi;

  dcl-s errsBefore int(10);

  errsBefore = gResult.errCount;

  jsCheckType(schemaIdx : dataIdx : errPath);
  jsCheckEnum(schemaIdx : dataIdx : errPath);
  jsCheckStringConstraints(schemaIdx : dataIdx : errPath);
  jsCheckNumberConstraints(schemaIdx : dataIdx : errPath);
  jsCheckArrayConstraints(schemaIdx : dataIdx : errPath);
  jsCheckRequired(schemaIdx : dataIdx : errPath);
  jsCheckProperties(schemaIdx : dataIdx : errPath);
  jsCheckItems(schemaIdx : dataIdx : errPath);

  return (gResult.errCount = errsBefore);
end-proc;

//---------------------------------------------------------------------
// "type": a string, or an array of acceptable type strings.
//---------------------------------------------------------------------
dcl-proc jsCheckType;
  dcl-pi *n ind;
    schemaIdx int(10) const;
    dataIdx   int(10) const;
    errPath   varchar(JS_MAXPATH) const;
  end-pi;

  dcl-s typeIdx  int(10);
  dcl-s itemIdx  int(10);
  dcl-s actual   varchar(10);
  dcl-s expected varchar(20);
  dcl-s list     varchar(200);
  dcl-s any      ind;
  dcl-s i        int(10);
  dcl-s n        int(10);

  typeIdx = jsonNodeObjectGet(gSchema:schemaIdx:'type');
  if typeIdx = JSON_NONODE;
    return *on;     // no "type" constraint
  endif;

  actual = jsonNodeType(gData:dataIdx);

  if jsonNodeType(gSchema:typeIdx) = JSONTYPE_ARRAY;
    n    = jsonNodeArrayCount(gSchema:typeIdx);
    any  = *off;
    list = '';
    for i = 0 to n - 1;
      itemIdx  = jsonNodeArrayItem(gSchema:typeIdx:i);
      expected = jsonNodeGetString(gSchema:itemIdx);
      if jsTypeMatches(expected:actual:dataIdx);
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
    expected = jsonNodeGetString(gSchema:typeIdx);
    if not jsTypeMatches(expected:actual:dataIdx);
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
    dataIdx  int(10) const;
  end-pi;

  if %trim(expected) = 'integer';
    return (actual = JSONTYPE_NUMBER and jsonNodeIsInteger(gData:dataIdx));
  endif;

  return (%trim(expected) = %trim(actual));
end-proc;

//---------------------------------------------------------------------
// "enum": value must equal one of a list of scalar literals.
// (Object/array enum members are not supported in the core subset.)
//---------------------------------------------------------------------
dcl-proc jsCheckEnum;
  dcl-pi *n ind;
    schemaIdx int(10) const;
    dataIdx   int(10) const;
    errPath   varchar(JS_MAXPATH) const;
  end-pi;

  dcl-s enumIdx    int(10);
  dcl-s candIdx    int(10);
  dcl-s actualType varchar(10);
  dcl-s candType   varchar(10);
  dcl-s found      ind;
  dcl-s i int(10);
  dcl-s n int(10);

  enumIdx = jsonNodeObjectGet(gSchema:schemaIdx:'enum');
  if enumIdx = JSON_NONODE;
    return *on;
  endif;

  n          = jsonNodeArrayCount(gSchema:enumIdx);
  actualType = jsonNodeType(gData:dataIdx);
  found      = *off;

  for i = 0 to n - 1;
    candIdx  = jsonNodeArrayItem(gSchema:enumIdx:i);
    candType = jsonNodeType(gSchema:candIdx);
    if candType = actualType;
      select;
        when actualType = JSONTYPE_STRING or actualType = JSONTYPE_BOOLEAN;
          if jsonNodeGetString(gSchema:candIdx) = jsonNodeGetString(gData:dataIdx);
            found = *on;
          endif;
        when actualType = JSONTYPE_NUMBER;
          if jsonNodeGetNumber(gSchema:candIdx) = jsonNodeGetNumber(gData:dataIdx);
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
    schemaIdx int(10) const;
    dataIdx   int(10) const;
    errPath   varchar(JS_MAXPATH) const;
  end-pi;

  dcl-s ok      ind;
  dcl-s sval    varchar(JSON_MAXVAL);
  dcl-s slen    int(10);
  dcl-s bound   int(10);
  dcl-s pattern varchar(JSON_MAXVAL);
  dcl-s boundIdx int(10);

  if jsonNodeType(gData:dataIdx) <> JSONTYPE_STRING;
    return *on;
  endif;

  ok   = *on;
  sval = jsonNodeGetString(gData:dataIdx);
  slen = %len(sval);

  boundIdx = jsonNodeObjectGet(gSchema:schemaIdx:'minLength');
  if boundIdx <> JSON_NONODE;
    bound = %int(jsonNodeGetNumber(gSchema:boundIdx));
    if slen < bound;
      jsAddError(errPath : 'length must be >= ' + %char(bound));
      ok = *off;
    endif;
  endif;

  boundIdx = jsonNodeObjectGet(gSchema:schemaIdx:'maxLength');
  if boundIdx <> JSON_NONODE;
    bound = %int(jsonNodeGetNumber(gSchema:boundIdx));
    if slen > bound;
      jsAddError(errPath : 'length must be <= ' + %char(bound));
      ok = *off;
    endif;
  endif;

  boundIdx = jsonNodeObjectGet(gSchema:schemaIdx:'pattern');
  if boundIdx <> JSON_NONODE;
    pattern = jsonNodeGetString(gSchema:boundIdx);
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
    schemaIdx int(10) const;
    dataIdx   int(10) const;
    errPath   varchar(JS_MAXPATH) const;
  end-pi;

  dcl-s ok       ind;
  dcl-s nval     packed(31:10);
  dcl-s bound    packed(31:10);
  dcl-s boundIdx int(10);

  if jsonNodeType(gData:dataIdx) <> JSONTYPE_NUMBER;
    return *on;
  endif;

  ok   = *on;
  nval = jsonNodeGetNumber(gData:dataIdx);

  boundIdx = jsonNodeObjectGet(gSchema:schemaIdx:'minimum');
  if boundIdx <> JSON_NONODE;
    bound = jsonNodeGetNumber(gSchema:boundIdx);
    if nval < bound;
      jsAddError(errPath : 'must be >= ' + %trim(%char(bound)));
      ok = *off;
    endif;
  endif;

  boundIdx = jsonNodeObjectGet(gSchema:schemaIdx:'maximum');
  if boundIdx <> JSON_NONODE;
    bound = jsonNodeGetNumber(gSchema:boundIdx);
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
    schemaIdx int(10) const;
    dataIdx   int(10) const;
    errPath   varchar(JS_MAXPATH) const;
  end-pi;

  dcl-s ok       ind;
  dcl-s cnt      int(10);
  dcl-s bound    int(10);
  dcl-s boundIdx int(10);

  if jsonNodeType(gData:dataIdx) <> JSONTYPE_ARRAY;
    return *on;
  endif;

  ok  = *on;
  cnt = jsonNodeArrayCount(gData:dataIdx);

  boundIdx = jsonNodeObjectGet(gSchema:schemaIdx:'minItems');
  if boundIdx <> JSON_NONODE;
    bound = %int(jsonNodeGetNumber(gSchema:boundIdx));
    if cnt < bound;
      jsAddError(errPath : 'must contain >= ' + %char(bound) + ' items');
      ok = *off;
    endif;
  endif;

  boundIdx = jsonNodeObjectGet(gSchema:schemaIdx:'maxItems');
  if boundIdx <> JSON_NONODE;
    bound = %int(jsonNodeGetNumber(gSchema:boundIdx));
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
    schemaIdx int(10) const;
    dataIdx   int(10) const;
    errPath   varchar(JS_MAXPATH) const;
  end-pi;

  dcl-s reqIdx  int(10);
  dcl-s nameIdx int(10);
  dcl-s name    varchar(JSON_MAXKEYLEN);
  dcl-s ok      ind;
  dcl-s i int(10);
  dcl-s n int(10);

  reqIdx = jsonNodeObjectGet(gSchema:schemaIdx:'required');
  if reqIdx = JSON_NONODE;
    return *on;
  endif;

  if jsonNodeType(gData:dataIdx) <> JSONTYPE_OBJECT;
    return *on;    // "required" only meaningful for objects
  endif;

  ok = *on;
  n  = jsonNodeArrayCount(gSchema:reqIdx);

  for i = 0 to n - 1;
    nameIdx = jsonNodeArrayItem(gSchema:reqIdx:i);
    name    = jsonNodeGetString(gSchema:nameIdx);
    if not jsonNodeObjectHas(gData:dataIdx:name);
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
    schemaIdx int(10) const;
    dataIdx   int(10) const;
    errPath   varchar(JS_MAXPATH) const;
  end-pi;

  dcl-s propsIdx int(10);
  dcl-ds keys likeds(jsonKeyList_t);
  dcl-s ok ind;
  dcl-s childDataIdx   int(10);
  dcl-s childSchemaIdx int(10);
  dcl-s childErrPath   varchar(JS_MAXPATH);
  dcl-s i int(10);

  propsIdx = jsonNodeObjectGet(gSchema:schemaIdx:'properties');
  if propsIdx = JSON_NONODE;
    return *on;
  endif;

  if jsonNodeType(gData:dataIdx) <> JSONTYPE_OBJECT;
    return *on;    // "properties" only meaningful for objects
  endif;

  ok = *on;
  jsonNodeObjectKeys(gSchema:propsIdx:keys);

  for i = 1 to keys.count;
    childDataIdx = jsonNodeObjectGet(gData:dataIdx:keys.name(i));
    if childDataIdx <> JSON_NONODE;
      childSchemaIdx = jsonNodeObjectGet(gSchema:propsIdx:keys.name(i));
      childErrPath   = %trimr(errPath) + '.' + %trim(keys.name(i));
      if not jsValidateNode(childSchemaIdx:childDataIdx:childErrPath);
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
    schemaIdx int(10) const;
    dataIdx   int(10) const;
    errPath   varchar(JS_MAXPATH) const;
  end-pi;

  dcl-s itemsIdx     int(10);
  dcl-s childDataIdx int(10);
  dcl-s childErrPath varchar(JS_MAXPATH);
  dcl-s ok ind;
  dcl-s i int(10);
  dcl-s n int(10);

  itemsIdx = jsonNodeObjectGet(gSchema:schemaIdx:'items');
  if itemsIdx = JSON_NONODE;
    return *on;
  endif;

  if jsonNodeType(gData:dataIdx) <> JSONTYPE_ARRAY;
    return *on;    // "items" only meaningful for arrays
  endif;

  ok = *on;
  n  = jsonNodeArrayCount(gData:dataIdx);

  for i = 0 to n - 1;
    childDataIdx = jsonNodeArrayItem(gData:dataIdx:i);
    childErrPath = %trimr(errPath) + '[' + %char(i) + ']';
    if not jsValidateNode(itemsIdx:childDataIdx:childErrPath);
      ok = *off;
    endif;
  endfor;

  return ok;
end-proc;
