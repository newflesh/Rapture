//=====================================================================
// JSONSCHEMA_H - prototypes/constants for the JSON Schema validator.
//
// Supported keywords (core subset):
//   type (string or array-of-strings, including "integer"), required,
//   properties, items, enum, minimum, maximum, minLength, maxLength,
//   minItems, maxItems, pattern.
//
// Not supported (full draft-07 keywords): $ref/definitions, allOf/
// anyOf/oneOf/not, additionalProperties, dependencies, format,
// const, propertyNames, exclusiveMinimum/Maximum, contains,
// uniqueItems, multipleOf.
//=====================================================================

/copy 'src/copy/jsonparser_h.rpgle'

dcl-c JS_MAXERRORS 200;   // most violations reported per validation run
dcl-c JS_MAXMSG    256;
dcl-c JS_MAXPATH   1024;

dcl-ds jsError_t qualified template;
  instancePath varchar(JS_MAXPATH);
  message      varchar(JS_MAXMSG);
end-ds;

dcl-ds jsResult_t qualified template;
  valid    ind;
  errCount int(10);
  errors   likeds(jsError_t) dim(JS_MAXERRORS);
end-ds;

//---------------------------------------------------------------------
// jsonSchemaValidate - validate dataDoc against schemaDoc. Both are
// parsed from scratch by the hand-rolled parser in jsonparser.sqlrpgle
// (jsonParse) - if either fails to parse as JSON, that is reported as
// a single violation at "$" rather than attempting to validate.
// Returns *on if valid, *off otherwise; result.errors lists every
// violation found (up to JS_MAXERRORS), each with the instance path
// (e.g. $.address.zip) where the violation occurred.
//---------------------------------------------------------------------
dcl-pr jsonSchemaValidate ind;
  schemaDoc varchar(JSON_MAXDOC:4) const;
  dataDoc   varchar(JSON_MAXDOC:4) const;
  result    likeds(jsResult_t);
end-pr;
