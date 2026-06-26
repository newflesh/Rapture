Rapture
=======

A JSON Schema validator for IBM i, written in RPGLE (free-form
ILE RPG / SQLRPGLE). It reads an arbitrary JSON document and an
arbitrary JSON Schema document and reports whether the document is
valid, with a list of every violation found.

## Why no external library?

Generic JSON handling on IBM i is usually done with Scott Klement's
YAJL port, but that's a separate package you install yourself, and
this project intentionally avoids that dependency. It also avoids
relying on **Db2 for i's SQL/JSON support** (`JSON_TABLE`,
`JSON_VALUE`, etc.) for parsing - instead, `src/jsonparser.sqlrpgle`
is a real hand-rolled recursive-descent JSON parser (RFC 8259) written
in pure RPG. It tokenizes UTF-8 text directly into an in-memory node
tree, with no external library and no database engine involved in
parsing at all. The only SQL still in use is `REGEXP_LIKE`, for the
schema's `pattern` keyword - regex matching is a separate concern from
parsing, and reimplementing a regex engine by hand wasn't worth it.

Because parsing is hand-rolled, it's also more capable in a few ways
a thin SQL/JSON wrapper couldn't be: custom error messages with byte
position, `\uXXXX` escape decoding (including surrogate pairs for
characters outside the Basic Multilingual Plane), and direct
object-member enumeration (no need to work around SQL/JSON path
syntax having no wildcard for property names).

## Project layout

```
src/
  copy/
    jsonparser_h.rpgle     prototypes/constants - JSON parser/tree API
    jsonschema_h.rpgle      prototypes/constants - schema validator
  jsonparser.sqlrpgle        hand-rolled recursive-descent JSON parser
  jsonschema.sqlrpgle        the validator engine (recursive descent)
  jsvalidate.sqlrpgle         CLI program: reads 2 IFS files, validates
test/
  schema_person.json
  data_person_valid.json
  data_person_invalid.json
```

## Supported JSON Schema keywords (core subset)

`type` (including `"integer"`, and arrays of types), `required`,
`properties`, `items`, `enum`, `minimum`, `maximum`, `minLength`,
`maxLength`, `minItems`, `maxItems`, `pattern`.

**Not supported** (these would need a follow-up pass): `$ref`/
`definitions`, `allOf`/`anyOf`/`oneOf`/`not`, `additionalProperties`,
`dependencies`, `format`, `const`, `propertyNames`,
`exclusiveMinimum`/`exclusiveMaximum`, `contains`, `uniqueItems`,
`multipleOf`, `patternProperties`.

`pattern` is checked with `REGEXP_LIKE`, which uses a Java/ICU-style
regex engine rather than strict ECMA 262 - close enough for the vast
majority of real-world patterns (anchors, character classes,
quantifiers, `\d`/`\s`/`\w` all work), but not byte-for-byte identical
to the JSON Schema spec's reference engine.

## Known limits

- Documents up to 1 MB (`JSON_MAXDOC` in `jsonparser_h.rpgle`) - raise
  the constant and recompile if you need more.
- Up to 60,000 parsed nodes per document (`JSON_MAXNODES`) - each
  value and object member is one node; deeply nested or very wide
  documents could exhaust this.
- Scalar values up to 32,000 characters (`JSON_MAXVAL`).
- Numbers are parsed into `packed(31:10)` - about 21 integer digits
  plus 10 fractional digits. Numbers needing more precision than that
  (or outside that range) will lose precision.
- Up to 256 properties enumerated per object, 256 chars per property
  name (`JSON_MAXKEYS`/`JSON_MAXKEYLEN`).
- Up to 200 violations reported per run (`JS_MAXERRORS`); validation
  keeps going past that, it just stops recording new ones.
- Malformed JSON in either the schema or the data document is
  reported as a single violation at `$` rather than a per-token parse
  error list.

## Building

Compile the two service-style modules, then the main program, then
bind. Run from the IBM i (5250, ACS Run SQL Scripts won't do CRTSQLRPGI -
use a 5250 session, an ACS "Submit job" with CL, or VS Code's Code for
IBM i extension):

```
CRTSQLRPGI OBJ(MYLIB/JSONPARSER) SRCSTMF('/path/to/Rapture/src/jsonparser.sqlrpgle') OBJTYPE(*MODULE) COMMIT(*NONE) INCDIR('/path/to/Rapture')
CRTSQLRPGI OBJ(MYLIB/JSONSCHEMA) SRCSTMF('/path/to/Rapture/src/jsonschema.sqlrpgle') OBJTYPE(*MODULE) COMMIT(*NONE) INCDIR('/path/to/Rapture')
CRTSQLRPGI OBJ(MYLIB/JSVALIDATE) SRCSTMF('/path/to/Rapture/src/jsvalidate.sqlrpgle') OBJTYPE(*MODULE) COMMIT(*NONE) INCDIR('/path/to/Rapture')

CRTPGM PGM(MYLIB/JSVALIDATE) MODULE(MYLIB/JSONPARSER MYLIB/JSONSCHEMA MYLIB/JSVALIDATE) ENTMOD(MYLIB/JSVALIDATE)
```

(`INCDIR` is the directory the `/copy 'src/copy/...'` statements are
resolved relative to - point it at wherever you cloned this repo.)

## Running

```
CALL PGM(MYLIB/JSVALIDATE) PARM('/path/to/Rapture/test/schema_person.json' '/path/to/Rapture/test/data_person_valid.json')
```

Output goes to `DSPLY` (job log / interactive display). Expected
results with the sample fixtures:

- `data_person_valid.json` -> `PASS: data is valid according to the schema.`
- `data_person_invalid.json` -> `FAIL: 5 violation(s) found:` listing
  the empty `name`, negative `age`, malformed `email`, disallowed
  `role`, and the empty string in `tags[1]`.

For batch/non-interactive use, swap the `DSPLY` calls in
`src/jsvalidate.sqlrpgle` for writing to `*PRINT`, an output file, or
an IFS file, since `DSPLY` only goes to the job log.

## Calling the validator from your own program

The actual reusable API is `jsonSchemaValidate` in
`src/jsonschema.sqlrpgle` / `src/copy/jsonschema_h.rpgle` - bind your
own program against the `JSONPARSER` and `JSONSCHEMA` modules and call:

```rpgle
/copy 'src/copy/jsonschema_h.rpgle'

dcl-ds result likeds(jsResult_t);
dcl-s ok ind;

ok = jsonSchemaValidate(mySchemaText : myDataText : result);
```

`mySchemaText`/`myDataText` are the full JSON documents as UTF-8 text
(CCSID 1208) - load them however suits your program (IFS file, table
column, HTTP response body, etc.), not just from files.
