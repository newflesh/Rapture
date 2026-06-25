**free
//=====================================================================
// JSONUTIL - generic JSON access built on Db2 for i's native SQL/JSON
// functions. No external library dependency.
//
// The one operation standard SQL/JSON path syntax cannot do is
// enumerate an object's member names (there is no wildcard for
// member names the way [*] is a wildcard for array elements), so
// jsonObjectKeys() walks the raw text returned by JSON_QUERY with a
// small bracket/quote-depth scanner instead of a path expression.
// Everything else here is a thin wrapper over JSON_EXISTS, JSON_VALUE,
// JSON_QUERY, JSON_TABLE and REGEXP_LIKE.
//=====================================================================
ctl-opt nomain;

exec sql include sqlca;

/copy 'src/copy/jsonutil_h.rpgle'

//---------------------------------------------------------------------
dcl-proc jsonExists export;
  dcl-pi *n ind;
    doc  varchar(JSON_MAXDOC:4) const;
    path varchar(JSON_MAXPATH) const;
  end-pi;

  dcl-s found int(10);

  exec sql
    select case when json_exists(:doc, cast(:path as varchar(1024)))
                then 1 else 0 end
      into :found
      from sysibm.sysdummy1;

  return (found = 1);
end-proc;

//---------------------------------------------------------------------
// jsonType - JSON_QUERY normally returns NULL for scalar results
// (its job is extracting objects/arrays), so we force every result
// to be array-wrapped with "WITH UNCONDITIONAL ARRAY WRAPPER" and
// look at the character right after the wrapper's opening bracket:
//   ["..  -> string     [42..   -> number
//   [tru.. / [fal.. -> boolean  [nul..  -> null
//   [{...    -> object          [[...   -> array
// This preserves the string/number/boolean distinction that
// JSON_VALUE alone would lose (it stringifies everything).
//---------------------------------------------------------------------
dcl-proc jsonType export;
  dcl-pi *n varchar(10);
    doc  varchar(JSON_MAXDOC:4) const;
    path varchar(JSON_MAXPATH) const;
  end-pi;

  dcl-s wrapped     varchar(JSON_MAXVAL) ccsid(*utf8);
  dcl-s wrappedNull int(10);
  dcl-s c2          char(1) ccsid(*utf8);

  if not jsonExists(doc:path);
    return JSONTYPE_NONE;
  endif;

  exec sql
    select json_query(:doc, cast(:path as varchar(1024))
                       returning varchar(32000)
                       with unconditional array wrapper
                       null on error)
      into :wrapped :wrappedNull
      from sysibm.sysdummy1;

  if wrappedNull < 0 or %len(wrapped) < 2;
    return JSONTYPE_NONE;
  endif;

  c2 = %subst(wrapped:2:1);

  select;
    when c2 = '"';
      return JSONTYPE_STRING;
    when c2 = '{';
      return JSONTYPE_OBJECT;
    when c2 = '[';
      return JSONTYPE_ARRAY;
    when c2 = 't' or c2 = 'f';
      return JSONTYPE_BOOLEAN;
    when c2 = 'n';
      return JSONTYPE_NULL;
    other;
      return JSONTYPE_NUMBER;
  endsl;
end-proc;

//---------------------------------------------------------------------
dcl-proc jsonGetString export;
  dcl-pi *n varchar(JSON_MAXVAL);
    doc  varchar(JSON_MAXDOC:4) const;
    path varchar(JSON_MAXPATH) const;
  end-pi;

  dcl-s val     varchar(JSON_MAXVAL) ccsid(*utf8);
  dcl-s valNull int(10);

  exec sql
    select json_value(:doc, cast(:path as varchar(1024))
                       returning varchar(32000)
                       null on empty null on error)
      into :val :valNull
      from sysibm.sysdummy1;

  if valNull < 0;
    return '';
  endif;

  return val;
end-proc;

//---------------------------------------------------------------------
dcl-proc jsonGetNumber export;
  dcl-pi *n packed(31:10);
    doc  varchar(JSON_MAXDOC:4) const;
    path varchar(JSON_MAXPATH) const;
  end-pi;

  dcl-s val     packed(31:10);
  dcl-s valNull int(10);

  exec sql
    select json_value(:doc, cast(:path as varchar(1024))
                       returning decimal(31,10)
                       null on empty null on error)
      into :val :valNull
      from sysibm.sysdummy1;

  if valNull < 0;
    return 0;
  endif;

  return val;
end-proc;

//---------------------------------------------------------------------
dcl-proc jsonIsIntegerValue export;
  dcl-pi *n ind;
    doc  varchar(JSON_MAXDOC:4) const;
    path varchar(JSON_MAXPATH) const;
  end-pi;

  dcl-s val     packed(31:10);
  dcl-s valNull int(10);
  dcl-s isInt   int(10);

  exec sql
    select json_value(:doc, cast(:path as varchar(1024))
                       returning decimal(31,10)
                       null on empty null on error)
      into :val :valNull
      from sysibm.sysdummy1;

  if valNull < 0;
    return *off;
  endif;

  exec sql
    select case when :val = floor(:val) then 1 else 0 end
      into :isInt
      from sysibm.sysdummy1;

  return (isInt = 1);
end-proc;

//---------------------------------------------------------------------
dcl-proc jsonArrayCount export;
  dcl-pi *n int(10);
    doc  varchar(JSON_MAXDOC:4) const;
    path varchar(JSON_MAXPATH) const;
  end-pi;

  dcl-s cnt     int(10);
  dcl-s arrPath varchar(JSON_MAXPATH);

  arrPath = %trimr(path) + '[*]';

  exec sql
    select count(*)
      into :cnt
      from json_table(:doc, cast(:arrPath as varchar(1024))
                       columns(idx for ordinality,
                               val varchar(32000) format json)) as t;

  return cnt;
end-proc;

//---------------------------------------------------------------------
// jsonObjectKeys - see header comment in jsonutil_h.rpgle. Pulls the
// object's raw JSON text via JSON_QUERY, then scans for top-level
// (brace-depth 1) quoted keys, tracking string-escape state so quotes
// inside string values/keys don't confuse the bracket depth count.
//---------------------------------------------------------------------
dcl-proc jsonObjectKeys export;
  dcl-pi *n;
    doc  varchar(JSON_MAXDOC:4) const;
    path varchar(JSON_MAXPATH) const;
    keys likeds(jsonKeyList_t);
  end-pi;

  dcl-s raw     varchar(JSON_MAXVAL) ccsid(*utf8);
  dcl-s rawNull int(10);
  dcl-s i      int(10);
  dcl-s len    int(10);
  dcl-s depth  int(10);
  dcl-s inStr  ind;
  dcl-s esc    ind;
  dcl-s keyStart   int(10);
  dcl-s keyEnd     int(10);
  dcl-s ch         char(1) ccsid(*utf8);
  dcl-s expectKey  ind;

  keys.count = 0;

  exec sql
    select json_query(:doc, cast(:path as varchar(1024))
                       returning varchar(32000)
                       null on empty null on error)
      into :raw :rawNull
      from sysibm.sysdummy1;

  if rawNull < 0;
    return;   // absent / not extractable - no keys
  endif;

  len = %len(raw);

  if len < 1 or %subst(raw:1:1) <> '{';
    return;   // not an object - no keys
  endif;

  depth     = 0;
  inStr     = *off;
  esc       = *off;
  expectKey = *on;     // true while the next quoted string at depth 1 is a key
  keyStart  = 0;

  for i = 1 to len;
    ch = %subst(raw:i:1);

    if inStr;
      if esc;
        esc = *off;
      elseif ch = '\';
        esc = *on;
      elseif ch = '"';
        inStr = *off;
        if expectKey and depth = 1;
          keyEnd = i - 1;
          if keys.count < JSON_MAXKEYS;
            keys.count += 1;
            if keyEnd >= keyStart;
              keys.name(keys.count) = %subst(raw:keyStart:keyEnd-keyStart+1);
            else;
              keys.name(keys.count) = '';
            endif;
          endif;
          expectKey = *off;   // next token at depth 1 is ':' + value, not a key
        endif;
      endif;
    else;
      if ch = '"';
        inStr = *on;
        if expectKey and depth = 1;
          keyStart = i + 1;
        endif;
      elseif ch = '{' or ch = '[';
        depth += 1;
      elseif ch = '}' or ch = ']';
        depth -= 1;
      elseif ch = ',' and depth = 1;
        expectKey = *on;     // next quoted string at depth 1 is a new key
      endif;
    endif;
  endfor;
end-proc;

//---------------------------------------------------------------------
dcl-proc jsonRegexMatch export;
  dcl-pi *n ind;
    value   varchar(JSON_MAXVAL) const;
    pattern varchar(JSON_MAXVAL) const;
  end-pi;

  dcl-s matched int(10);

  exec sql
    select case when regexp_like(:value, :pattern) then 1 else 0 end
      into :matched
      from sysibm.sysdummy1;

  return (matched = 1);
end-proc;

//---------------------------------------------------------------------
dcl-proc jsonPathSeg export;
  dcl-pi *n varchar(JSON_MAXPATH);
    parentPath varchar(JSON_MAXPATH) const;
    key        varchar(JSON_MAXKEYLEN) const;
  end-pi;

  dcl-s escaped varchar(JSON_MAXKEYLEN * 2);
  dcl-s i  int(10);
  dcl-s ch char(1);

  escaped = '';
  for i = 1 to %len(%trimr(key));
    ch = %subst(key:i:1);
    if ch = '"' or ch = '\';
      escaped += '\' + ch;
    else;
      escaped += ch;
    endif;
  endfor;

  return %trimr(parentPath) + '."' + escaped + '"';
end-proc;

//---------------------------------------------------------------------
dcl-proc jsonPathIdx export;
  dcl-pi *n varchar(JSON_MAXPATH);
    parentPath varchar(JSON_MAXPATH) const;
    idx        int(10) const;
  end-pi;

  return %trimr(parentPath) + '[' + %char(idx) + ']';
end-proc;
