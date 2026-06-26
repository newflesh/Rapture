**free
//=====================================================================
// JSONPARSER - hand-rolled recursive-descent JSON parser (RFC 8259).
//
// Parses arbitrary JSON text into an in-memory node tree (jsonDoc_t),
// with no external library and no Db2 SQL/JSON dependency for the
// parsing itself. Strings/numbers are kept as (start,len) spans into
// the original source text; values are decoded on demand by the
// accessor procs below. REGEXP_LIKE (SQL) is still used for the
// "pattern" schema keyword only - that's regex matching, not parsing.
//=====================================================================
ctl-opt nomain;

exec sql include sqlca;

/copy 'src/copy/jsonparser_h.rpgle'

//---------------------------------------------------------------------
// forward prototypes for internal (non-exported) recursive-descent
// and helper procedures
//---------------------------------------------------------------------
dcl-pr skipWs;
  doc likeds(jsonDoc_t);
  pos int(10);
end-pr;

dcl-pr setErr;
  doc    likeds(jsonDoc_t);
  pos    int(10) const;
  msg    varchar(120) const;
end-pr;

dcl-pr newNode int(10);
  doc       likeds(jsonDoc_t);
  parentIdx int(10) const;
end-pr;

dcl-pr isDigit ind;
  ch char(1) const;
end-pr;

dcl-pr parseValue int(10);
  doc       likeds(jsonDoc_t);
  pos       int(10);
  parentIdx int(10) const;
end-pr;

dcl-pr parseObject int(10);
  doc       likeds(jsonDoc_t);
  pos       int(10);
  parentIdx int(10) const;
end-pr;

dcl-pr parseArray int(10);
  doc       likeds(jsonDoc_t);
  pos       int(10);
  parentIdx int(10) const;
end-pr;

dcl-pr parseStringValue int(10);
  doc       likeds(jsonDoc_t);
  pos       int(10);
  parentIdx int(10) const;
end-pr;

dcl-pr parseStringSpan ind;
  doc      likeds(jsonDoc_t);
  pos      int(10);
  rawStart int(10);
  rawLen   int(10);
end-pr;

dcl-pr parseNumber int(10);
  doc       likeds(jsonDoc_t);
  pos       int(10);
  parentIdx int(10) const;
end-pr;

dcl-pr parseLiteral int(10);
  doc       likeds(jsonDoc_t);
  pos       int(10);
  parentIdx int(10) const;
end-pr;

dcl-pr decodeSpan varchar(JSON_MAXVAL);
  doc    likeds(jsonDoc_t) const;
  start  int(10) const;
  length int(10) const;
end-pr;

dcl-pr hexNibble uns(5);
  ch char(1) const;
end-pr;

dcl-pr hex4 uns(5);
  doc likeds(jsonDoc_t) const;
  pos int(10) const;
end-pr;

//=====================================================================
dcl-proc jsonParse export;
  dcl-pi *n ind;
    text varchar(JSON_MAXDOC:4) const;
    doc  likeds(jsonDoc_t);
  end-pi;

  dcl-s pos int(10);

  doc.text      = text;
  doc.nodeCount = 0;
  doc.rootIdx   = JSON_NONODE;
  doc.ok        = *on;
  doc.errPos    = 0;
  doc.errMsg    = '';

  pos = 1;
  skipWs(doc:pos);

  if pos > %len(doc.text);
    setErr(doc:pos:'empty document - expected a JSON value');
    return *off;
  endif;

  doc.rootIdx = parseValue(doc:pos:JSON_NONODE);
  if doc.rootIdx = JSON_NONODE;
    return *off;
  endif;

  skipWs(doc:pos);
  if pos <= %len(doc.text);
    setErr(doc:pos:'trailing characters after JSON value');
    return *off;
  endif;

  return *on;
end-proc;

//---------------------------------------------------------------------
dcl-proc skipWs;
  dcl-pi *n;
    doc likeds(jsonDoc_t);
    pos int(10);
  end-pi;

  dcl-s ch char(1) ccsid(*utf8);

  dow pos <= %len(doc.text);
    ch = %subst(doc.text:pos:1);
    if ch = ' ' or ch = x'09' or ch = x'0A' or ch = x'0D';
      pos += 1;
    else;
      leave;
    endif;
  enddo;
end-proc;

//---------------------------------------------------------------------
dcl-proc setErr;
  dcl-pi *n;
    doc likeds(jsonDoc_t);
    pos int(10) const;
    msg varchar(120) const;
  end-pi;

  if doc.ok;            // keep only the first error encountered
    doc.ok     = *off;
    doc.errPos = pos;
    doc.errMsg = msg;
  endif;
end-proc;

//---------------------------------------------------------------------
dcl-proc isDigit;
  dcl-pi *n ind;
    ch char(1) const;
  end-pi;

  return (ch >= '0' and ch <= '9');
end-proc;

//---------------------------------------------------------------------
dcl-proc newNode;
  dcl-pi *n int(10);
    doc       likeds(jsonDoc_t);
    parentIdx int(10) const;
  end-pi;

  dcl-s idx int(10);

  if doc.nodeCount >= JSON_MAXNODES;
    setErr(doc:0:'document too complex (raise JSON_MAXNODES)');
    return JSON_NONODE;
  endif;

  doc.nodeCount += 1;
  idx = doc.nodeCount;

  doc.nodes(idx).kind       = '';
  doc.nodes(idx).parent     = parentIdx;
  doc.nodes(idx).firstChild = JSON_NONODE;
  doc.nodes(idx).lastChild  = JSON_NONODE;
  doc.nodes(idx).nextSib    = JSON_NONODE;
  doc.nodes(idx).childCount = 0;
  doc.nodes(idx).keyStart   = 0;
  doc.nodes(idx).keyLen     = 0;
  doc.nodes(idx).valStart   = 0;
  doc.nodes(idx).valLen     = 0;
  doc.nodes(idx).boolVal    = *off;

  if parentIdx <> JSON_NONODE;
    if doc.nodes(parentIdx).firstChild = JSON_NONODE;
      doc.nodes(parentIdx).firstChild = idx;
    else;
      doc.nodes(doc.nodes(parentIdx).lastChild).nextSib = idx;
    endif;
    doc.nodes(parentIdx).lastChild = idx;
    doc.nodes(parentIdx).childCount += 1;
  endif;

  return idx;
end-proc;

//---------------------------------------------------------------------
dcl-proc parseValue;
  dcl-pi *n int(10);
    doc       likeds(jsonDoc_t);
    pos       int(10);
    parentIdx int(10) const;
  end-pi;

  dcl-s ch char(1) ccsid(*utf8);

  skipWs(doc:pos);

  if pos > %len(doc.text);
    setErr(doc:pos:'unexpected end of input');
    return JSON_NONODE;
  endif;

  ch = %subst(doc.text:pos:1);

  select;
    when ch = '{';
      return parseObject(doc:pos:parentIdx);
    when ch = '[';
      return parseArray(doc:pos:parentIdx);
    when ch = '"';
      return parseStringValue(doc:pos:parentIdx);
    when ch = 't' or ch = 'f' or ch = 'n';
      return parseLiteral(doc:pos:parentIdx);
    when ch = '-' or isDigit(ch);
      return parseNumber(doc:pos:parentIdx);
    other;
      setErr(doc:pos:'unexpected character - expected a JSON value');
      return JSON_NONODE;
  endsl;
end-proc;

//---------------------------------------------------------------------
dcl-proc parseObject;
  dcl-pi *n int(10);
    doc       likeds(jsonDoc_t);
    pos       int(10);
    parentIdx int(10) const;
  end-pi;

  dcl-s objIdx    int(10);
  dcl-s childIdx  int(10);
  dcl-s keyStart  int(10);
  dcl-s keyLen    int(10);
  dcl-s ch        char(1) ccsid(*utf8);

  objIdx = newNode(doc:parentIdx);
  if objIdx = JSON_NONODE;
    return JSON_NONODE;
  endif;
  doc.nodes(objIdx).kind = JSONTYPE_OBJECT;

  pos += 1;            // consume '{'
  skipWs(doc:pos);

  if pos <= %len(doc.text) and %subst(doc.text:pos:1) = '}';
    pos += 1;
    return objIdx;      // empty object
  endif;

  dow (1 = 1);
    skipWs(doc:pos);

    if pos > %len(doc.text) or %subst(doc.text:pos:1) <> '"';
      setErr(doc:pos:'expected a quoted property name');
      return JSON_NONODE;
    endif;

    if not parseStringSpan(doc:pos:keyStart:keyLen);
      return JSON_NONODE;
    endif;

    skipWs(doc:pos);
    if pos > %len(doc.text) or %subst(doc.text:pos:1) <> ':';
      setErr(doc:pos:'expected '':'' after property name');
      return JSON_NONODE;
    endif;
    pos += 1;           // consume ':'

    childIdx = parseValue(doc:pos:objIdx);
    if childIdx = JSON_NONODE;
      return JSON_NONODE;
    endif;
    doc.nodes(childIdx).keyStart = keyStart;
    doc.nodes(childIdx).keyLen   = keyLen;

    skipWs(doc:pos);
    if pos > %len(doc.text);
      setErr(doc:pos:'unterminated object');
      return JSON_NONODE;
    endif;

    ch = %subst(doc.text:pos:1);
    if ch = ',';
      pos += 1;
      iter;
    elseif ch = '}';
      pos += 1;
      leave;
    else;
      setErr(doc:pos:'expected '','' or ''}''');
      return JSON_NONODE;
    endif;
  enddo;

  return objIdx;
end-proc;

//---------------------------------------------------------------------
dcl-proc parseArray;
  dcl-pi *n int(10);
    doc       likeds(jsonDoc_t);
    pos       int(10);
    parentIdx int(10) const;
  end-pi;

  dcl-s arrIdx   int(10);
  dcl-s childIdx int(10);
  dcl-s ch       char(1) ccsid(*utf8);

  arrIdx = newNode(doc:parentIdx);
  if arrIdx = JSON_NONODE;
    return JSON_NONODE;
  endif;
  doc.nodes(arrIdx).kind = JSONTYPE_ARRAY;

  pos += 1;            // consume '['
  skipWs(doc:pos);

  if pos <= %len(doc.text) and %subst(doc.text:pos:1) = ']';
    pos += 1;
    return arrIdx;      // empty array
  endif;

  dow (1 = 1);
    childIdx = parseValue(doc:pos:arrIdx);
    if childIdx = JSON_NONODE;
      return JSON_NONODE;
    endif;

    skipWs(doc:pos);
    if pos > %len(doc.text);
      setErr(doc:pos:'unterminated array');
      return JSON_NONODE;
    endif;

    ch = %subst(doc.text:pos:1);
    if ch = ',';
      pos += 1;
      iter;
    elseif ch = ']';
      pos += 1;
      leave;
    else;
      setErr(doc:pos:'expected '','' or '']''');
      return JSON_NONODE;
    endif;
  enddo;

  return arrIdx;
end-proc;

//---------------------------------------------------------------------
dcl-proc parseStringValue;
  dcl-pi *n int(10);
    doc       likeds(jsonDoc_t);
    pos       int(10);
    parentIdx int(10) const;
  end-pi;

  dcl-s strIdx   int(10);
  dcl-s rawStart int(10);
  dcl-s rawLen   int(10);

  strIdx = newNode(doc:parentIdx);
  if strIdx = JSON_NONODE;
    return JSON_NONODE;
  endif;

  if not parseStringSpan(doc:pos:rawStart:rawLen);
    return JSON_NONODE;
  endif;

  doc.nodes(strIdx).kind     = JSONTYPE_STRING;
  doc.nodes(strIdx).valStart = rawStart;
  doc.nodes(strIdx).valLen   = rawLen;

  return strIdx;
end-proc;

//---------------------------------------------------------------------
// parseStringSpan - assumes doc.text(pos) = '"'. Advances pos past
// the closing quote and returns the raw span *between* the quotes
// (still escaped - decodeSpan() unescapes it later). Validates escape
// sequences and rejects raw control characters, but does not allocate
// a node (used for both string values and object property names).
//---------------------------------------------------------------------
dcl-proc parseStringSpan;
  dcl-pi *n ind;
    doc      likeds(jsonDoc_t);
    pos      int(10);
    rawStart int(10);
    rawLen   int(10);
  end-pi;

  dcl-s ch   char(1) ccsid(*utf8);
  dcl-s hc   char(1) ccsid(*utf8);
  dcl-s k    int(10);
  dcl-s len  int(10);

  len = %len(doc.text);
  pos += 1;             // consume opening quote
  rawStart = pos;

  dow (1 = 1);
    if pos > len;
      setErr(doc:pos:'unterminated string');
      return *off;
    endif;

    ch = %subst(doc.text:pos:1);

    if ch = '"';
      rawLen = pos - rawStart;
      pos += 1;          // consume closing quote
      return *on;
    elseif ch = '\';
      if pos + 1 > len;
        setErr(doc:pos:'unterminated escape sequence');
        return *off;
      endif;
      hc = %subst(doc.text:pos+1:1);
      select;
        when hc = '"' or hc = '\' or hc = '/' or hc = 'b'
          or hc = 'f' or hc = 'n' or hc = 'r' or hc = 't';
          pos += 2;
        when hc = 'u';
          if pos + 5 > len;
            setErr(doc:pos:'invalid \u escape');
            return *off;
          endif;
          for k = 1 to 4;
            hc = %subst(doc.text:pos+1+k:1);
            if not (isDigit(hc) or (hc >= 'a' and hc <= 'f')
                                 or (hc >= 'A' and hc <= 'F'));
              setErr(doc:pos:'invalid \u escape');
              return *off;
            endif;
          endfor;
          pos += 6;
        other;
          setErr(doc:pos:'invalid escape sequence');
          return *off;
      endsl;
    elseif ch < x'20';
      setErr(doc:pos:'control character not allowed in string');
      return *off;
    else;
      pos += 1;
    endif;
  enddo;
end-proc;

//---------------------------------------------------------------------
dcl-proc parseNumber;
  dcl-pi *n int(10);
    doc       likeds(jsonDoc_t);
    pos       int(10);
    parentIdx int(10) const;
  end-pi;

  dcl-s numIdx int(10);
  dcl-s start  int(10);
  dcl-s len    int(10);

  numIdx = newNode(doc:parentIdx);
  if numIdx = JSON_NONODE;
    return JSON_NONODE;
  endif;

  len   = %len(doc.text);
  start = pos;

  if pos <= len and %subst(doc.text:pos:1) = '-';
    pos += 1;
  endif;

  if pos > len or not isDigit(%subst(doc.text:pos:1));
    setErr(doc:pos:'invalid number');
    return JSON_NONODE;
  endif;

  if %subst(doc.text:pos:1) = '0';
    pos += 1;
  else;
    dow pos <= len and isDigit(%subst(doc.text:pos:1));
      pos += 1;
    enddo;
  endif;

  if pos <= len and %subst(doc.text:pos:1) = '.';
    pos += 1;
    if pos > len or not isDigit(%subst(doc.text:pos:1));
      setErr(doc:pos:'invalid number - digits expected after ''.''');
      return JSON_NONODE;
    endif;
    dow pos <= len and isDigit(%subst(doc.text:pos:1));
      pos += 1;
    enddo;
  endif;

  if pos <= len and (%subst(doc.text:pos:1) = 'e' or %subst(doc.text:pos:1) = 'E');
    pos += 1;
    if pos <= len and (%subst(doc.text:pos:1) = '+' or %subst(doc.text:pos:1) = '-');
      pos += 1;
    endif;
    if pos > len or not isDigit(%subst(doc.text:pos:1));
      setErr(doc:pos:'invalid number - digits expected in exponent');
      return JSON_NONODE;
    endif;
    dow pos <= len and isDigit(%subst(doc.text:pos:1));
      pos += 1;
    enddo;
  endif;

  doc.nodes(numIdx).kind     = JSONTYPE_NUMBER;
  doc.nodes(numIdx).valStart = start;
  doc.nodes(numIdx).valLen   = pos - start;

  return numIdx;
end-proc;

//---------------------------------------------------------------------
dcl-proc parseLiteral;
  dcl-pi *n int(10);
    doc       likeds(jsonDoc_t);
    pos       int(10);
    parentIdx int(10) const;
  end-pi;

  dcl-s litIdx int(10);
  dcl-s len    int(10);

  len = %len(doc.text);

  litIdx = newNode(doc:parentIdx);
  if litIdx = JSON_NONODE;
    return JSON_NONODE;
  endif;

  if pos + 3 <= len and %subst(doc.text:pos:4) = 'true';
    doc.nodes(litIdx).kind    = JSONTYPE_BOOLEAN;
    doc.nodes(litIdx).boolVal = *on;
    pos += 4;
  elseif pos + 4 <= len and %subst(doc.text:pos:5) = 'false';
    doc.nodes(litIdx).kind    = JSONTYPE_BOOLEAN;
    doc.nodes(litIdx).boolVal = *off;
    pos += 5;
  elseif pos + 3 <= len and %subst(doc.text:pos:4) = 'null';
    doc.nodes(litIdx).kind = JSONTYPE_NULL;
    pos += 4;
  else;
    setErr(doc:pos:'invalid literal - expected true, false or null');
    return JSON_NONODE;
  endif;

  return litIdx;
end-proc;

//---------------------------------------------------------------------
// decodeSpan - unescape a raw (still-escaped) string span into a
// regular UTF-8 value. \uXXXX is converted via a UCS-2 byte overlay
// so the CCSID conversion engine produces the correct UTF-8 bytes;
// surrogate pairs (codepoints above U+FFFF) are detected and combined
// into a single 4-byte UCS-2 unit so they convert correctly too.
//---------------------------------------------------------------------
dcl-proc decodeSpan;
  dcl-pi *n varchar(JSON_MAXVAL);
    doc    likeds(jsonDoc_t) const;
    start  int(10) const;
    length int(10) const;
  end-pi;

  dcl-ds ucs2Word qualified template;
    raw char(2) ccsid(1200) pos(1);
    val uns(5)              pos(1);
  end-ds;
  dcl-ds hi likeds(ucs2Word);
  dcl-ds lo likeds(ucs2Word);
  dcl-ds pair qualified;
    raw char(4) ccsid(1200);
  end-ds;

  dcl-s out varchar(JSON_MAXVAL) ccsid(*utf8);
  dcl-s ch  char(1) ccsid(*utf8);
  dcl-s hc  char(1) ccsid(*utf8);
  dcl-s i   int(10);
  dcl-s endPos int(10);
  dcl-s cp  uns(5);
  dcl-s cp2 uns(5);

  out    = '';
  i      = start;
  endPos = start + length - 1;

  dow i <= endPos;
    ch = %subst(doc.text:i:1);

    if ch <> '\';
      out += ch;
      i += 1;
      iter;
    endif;

    hc = %subst(doc.text:i+1:1);
    select;
      when hc = '"' or hc = '\' or hc = '/';
        out += hc;
        i += 2;
      when hc = 'b';
        out += x'08';
        i += 2;
      when hc = 'f';
        out += x'0C';
        i += 2;
      when hc = 'n';
        out += x'0A';
        i += 2;
      when hc = 'r';
        out += x'0D';
        i += 2;
      when hc = 't';
        out += x'09';
        i += 2;
      when hc = 'u';
        cp   = hex4(doc:i+2);
        i   += 6;
        if cp >= 55296 and cp <= 56319
           and i + 1 <= endPos
           and %subst(doc.text:i:1) = '\'
           and %subst(doc.text:i+1:1) = 'u';
          // high surrogate followed by another \u - check for low surrogate
          cp2 = hex4(doc:i+2);
          if cp2 >= 56320 and cp2 <= 57343;
            hi.val = cp;
            lo.val = cp2;
            pair.raw = hi.raw + lo.raw;
            out += pair.raw;
            i += 6;
            iter;
          endif;
        endif;
        hi.val = cp;
        out += hi.raw;
      other;
        // shouldn't happen - parseStringSpan validates escapes
        out += hc;
        i += 2;
    endsl;
  enddo;

  return out;
end-proc;

//---------------------------------------------------------------------
dcl-proc hexNibble;
  dcl-pi *n uns(5);
    ch char(1) const;
  end-pi;

  dcl-s p int(10);

  p = %scan(ch:'0123456789abcdef');
  if p > 0;
    return p - 1;
  endif;

  p = %scan(ch:'0123456789ABCDEF');
  if p > 0;
    return p - 1;
  endif;

  return 0;
end-proc;

//---------------------------------------------------------------------
dcl-proc hex4;
  dcl-pi *n uns(5);
    doc likeds(jsonDoc_t) const;
    pos int(10) const;
  end-pi;

  return hexNibble(%subst(doc.text:pos:1))   * 4096
       + hexNibble(%subst(doc.text:pos+1:1)) * 256
       + hexNibble(%subst(doc.text:pos+2:1)) * 16
       + hexNibble(%subst(doc.text:pos+3:1));
end-proc;

//=====================================================================
// tree accessors (exported)
//=====================================================================
dcl-proc jsonNodeType export;
  dcl-pi *n varchar(10);
    doc     likeds(jsonDoc_t) const;
    nodeIdx int(10) const;
  end-pi;

  if nodeIdx < 1 or nodeIdx > doc.nodeCount;
    return JSONTYPE_NONE;
  endif;

  return doc.nodes(nodeIdx).kind;
end-proc;

//---------------------------------------------------------------------
dcl-proc jsonNodeGetString export;
  dcl-pi *n varchar(JSON_MAXVAL);
    doc     likeds(jsonDoc_t) const;
    nodeIdx int(10) const;
  end-pi;

  if nodeIdx < 1 or nodeIdx > doc.nodeCount;
    return '';
  endif;

  select;
    when doc.nodes(nodeIdx).kind = JSONTYPE_STRING;
      return decodeSpan(doc:doc.nodes(nodeIdx).valStart:doc.nodes(nodeIdx).valLen);
    when doc.nodes(nodeIdx).kind = JSONTYPE_NUMBER;
      return %subst(doc.text:doc.nodes(nodeIdx).valStart:doc.nodes(nodeIdx).valLen);
    when doc.nodes(nodeIdx).kind = JSONTYPE_BOOLEAN;
      if doc.nodes(nodeIdx).boolVal;
        return 'true';
      else;
        return 'false';
      endif;
    other;
      return '';
  endsl;
end-proc;

//---------------------------------------------------------------------
dcl-proc jsonNodeGetNumber export;
  dcl-pi *n packed(31:10);
    doc     likeds(jsonDoc_t) const;
    nodeIdx int(10) const;
  end-pi;

  dcl-s raw      varchar(64) ccsid(*utf8);
  dcl-s mantissa varchar(64) ccsid(*utf8);
  dcl-s val      packed(31:10);
  dcl-s ePos     int(10);
  dcl-s exp      int(10);

  if nodeIdx < 1 or nodeIdx > doc.nodeCount or doc.nodes(nodeIdx).kind <> JSONTYPE_NUMBER;
    return 0;
  endif;

  raw = %subst(doc.text:doc.nodes(nodeIdx).valStart:doc.nodes(nodeIdx).valLen);

  ePos = %scan('e':raw);
  if ePos = 0;
    ePos = %scan('E':raw);
  endif;

  if ePos = 0;
    return %dec(raw:31:10);
  endif;

  mantissa = %subst(raw:1:ePos-1);
  exp      = %int(%subst(raw:ePos+1:%len(raw)-ePos));
  val      = %dec(mantissa:31:10);

  dow exp > 0;
    val *= 10;
    exp -= 1;
  enddo;
  dow exp < 0;
    val /= 10;
    exp += 1;
  enddo;

  return val;
end-proc;

//---------------------------------------------------------------------
dcl-proc jsonNodeGetBool export;
  dcl-pi *n ind;
    doc     likeds(jsonDoc_t) const;
    nodeIdx int(10) const;
  end-pi;

  if nodeIdx < 1 or nodeIdx > doc.nodeCount;
    return *off;
  endif;

  return doc.nodes(nodeIdx).boolVal;
end-proc;

//---------------------------------------------------------------------
dcl-proc jsonNodeIsInteger export;
  dcl-pi *n ind;
    doc     likeds(jsonDoc_t) const;
    nodeIdx int(10) const;
  end-pi;

  dcl-s val  packed(31:10);
  dcl-s ival packed(31:0);

  if nodeIdx < 1 or nodeIdx > doc.nodeCount or doc.nodes(nodeIdx).kind <> JSONTYPE_NUMBER;
    return *off;
  endif;

  val  = jsonNodeGetNumber(doc:nodeIdx);
  ival = val;

  return (val = ival);
end-proc;

//---------------------------------------------------------------------
dcl-proc jsonNodeKeyName export;
  dcl-pi *n varchar(JSON_MAXKEYLEN);
    doc     likeds(jsonDoc_t) const;
    nodeIdx int(10) const;
  end-pi;

  if nodeIdx < 1 or nodeIdx > doc.nodeCount or doc.nodes(nodeIdx).keyLen = 0;
    return '';
  endif;

  return decodeSpan(doc:doc.nodes(nodeIdx).keyStart:doc.nodes(nodeIdx).keyLen);
end-proc;

//---------------------------------------------------------------------
dcl-proc jsonNodeArrayCount export;
  dcl-pi *n int(10);
    doc     likeds(jsonDoc_t) const;
    nodeIdx int(10) const;
  end-pi;

  if nodeIdx < 1 or nodeIdx > doc.nodeCount or doc.nodes(nodeIdx).kind <> JSONTYPE_ARRAY;
    return 0;
  endif;

  return doc.nodes(nodeIdx).childCount;
end-proc;

//---------------------------------------------------------------------
dcl-proc jsonNodeArrayItem export;
  dcl-pi *n int(10);
    doc     likeds(jsonDoc_t) const;
    nodeIdx int(10) const;
    i       int(10) const;
  end-pi;

  dcl-s cur int(10);
  dcl-s k   int(10);

  if nodeIdx < 1 or nodeIdx > doc.nodeCount or doc.nodes(nodeIdx).kind <> JSONTYPE_ARRAY;
    return JSON_NONODE;
  endif;
  if i < 0 or i >= doc.nodes(nodeIdx).childCount;
    return JSON_NONODE;
  endif;

  cur = doc.nodes(nodeIdx).firstChild;
  for k = 1 to i;
    cur = doc.nodes(cur).nextSib;
  endfor;

  return cur;
end-proc;

//---------------------------------------------------------------------
dcl-proc jsonNodeObjectGet export;
  dcl-pi *n int(10);
    doc     likeds(jsonDoc_t) const;
    nodeIdx int(10) const;
    key     varchar(JSON_MAXKEYLEN) const;
  end-pi;

  dcl-s cur int(10);

  if nodeIdx < 1 or nodeIdx > doc.nodeCount or doc.nodes(nodeIdx).kind <> JSONTYPE_OBJECT;
    return JSON_NONODE;
  endif;

  cur = doc.nodes(nodeIdx).firstChild;
  dow cur <> JSON_NONODE;
    if jsonNodeKeyName(doc:cur) = %trimr(key);
      return cur;
    endif;
    cur = doc.nodes(cur).nextSib;
  enddo;

  return JSON_NONODE;
end-proc;

//---------------------------------------------------------------------
dcl-proc jsonNodeObjectHas export;
  dcl-pi *n ind;
    doc     likeds(jsonDoc_t) const;
    nodeIdx int(10) const;
    key     varchar(JSON_MAXKEYLEN) const;
  end-pi;

  return (jsonNodeObjectGet(doc:nodeIdx:key) <> JSON_NONODE);
end-proc;

//---------------------------------------------------------------------
dcl-proc jsonNodeObjectKeys export;
  dcl-pi *n;
    doc     likeds(jsonDoc_t) const;
    nodeIdx int(10) const;
    keys    likeds(jsonKeyList_t);
  end-pi;

  dcl-s cur int(10);

  keys.count = 0;

  if nodeIdx < 1 or nodeIdx > doc.nodeCount or doc.nodes(nodeIdx).kind <> JSONTYPE_OBJECT;
    return;
  endif;

  cur = doc.nodes(nodeIdx).firstChild;
  dow cur <> JSON_NONODE and keys.count < JSON_MAXKEYS;
    keys.count += 1;
    keys.name(keys.count) = jsonNodeKeyName(doc:cur);
    cur = doc.nodes(cur).nextSib;
  enddo;
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
