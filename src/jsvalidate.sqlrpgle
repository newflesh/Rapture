**free
//=====================================================================
// JSVALIDATE - command-line JSON Schema validator.
//
// Reads a JSON Schema file and a JSON data file from the IFS,
// validates the data against the schema, and reports PASS/FAIL plus
// every violation found (instance path + message) via DSPLY.
//
//   CALL PGM(JSVALIDATE) PARM('/path/to/schema.json' '/path/to/data.json')
//=====================================================================
ctl-opt main(main) dftactgrp(*no) actgrp(*new);

exec sql include sqlca;

/copy 'src/copy/jsonschema_h.rpgle'

dcl-pr readIfsFile;
  path varchar(1024) const;
  doc  varchar(JSON_MAXDOC:4);
end-pr;

//---------------------------------------------------------------------
dcl-proc main;
  dcl-pi *n;
    schemaPathArg char(1024) const;
    dataPathArg   char(1024) const;
  end-pi;

  dcl-s schemaDoc varchar(JSON_MAXDOC:4) ccsid(*utf8);
  dcl-s dataDoc   varchar(JSON_MAXDOC:4) ccsid(*utf8);
  dcl-ds result likeds(jsResult_t);
  dcl-s isValid ind;
  dcl-s i int(10);

  readIfsFile(%trimr(schemaPathArg) : schemaDoc);
  readIfsFile(%trimr(dataPathArg)   : dataDoc);

  isValid = jsonSchemaValidate(schemaDoc : dataDoc : result);

  if isValid;
    dsply 'PASS: data is valid according to the schema.';
  else;
    dsply ('FAIL: ' + %char(result.errCount) + ' violation(s) found:');
    for i = 1 to result.errCount;
      dsply (%trim(result.errors(i).instancePath) + ' - '
             + %trim(result.errors(i).message));
    endfor;
  endif;

  *inlr = *on;
end-proc;

//---------------------------------------------------------------------
// readIfsFile - read a stream file's full contents (assumed UTF-8
// JSON text) into doc, via the QSYS2.IFS_READ_UTF8 table function.
// Reads in a loop and concatenates rather than assuming the whole
// file comes back as a single row, since that depends on line length.
//---------------------------------------------------------------------
dcl-proc readIfsFile;
  dcl-pi *n;
    path varchar(1024) const;
    doc  varchar(JSON_MAXDOC:4) ccsid(*utf8);
  end-pi;

  dcl-s lineBuf varchar(32000) ccsid(*utf8);

  doc = '';

  exec sql
    declare ifsCur cursor for
      select line
        from table(qsys2.ifs_read_utf8(path_name => :path)) as x;

  exec sql open ifsCur;

  dow (1 = 1);
    exec sql fetch ifsCur into :lineBuf;
    if sqlcode <> 0;
      leave;
    endif;
    doc += lineBuf;
  enddo;

  exec sql close ifsCur;
end-proc;
