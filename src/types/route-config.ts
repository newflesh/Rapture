import { z } from 'zod';

export const ParameterSource = z.enum(['path', 'query', 'body', 'header']);
export type ParameterSource = z.infer<typeof ParameterSource>;

export const ParameterDirection = z.enum(['IN', 'OUT', 'INOUT']);
export type ParameterDirection = z.infer<typeof ParameterDirection>;

export const ParameterType = z.enum([
  'CHAR',
  'VARCHAR',
  'DECIMAL',
  'NUMERIC',
  'INTEGER',
  'SMALLINT',
  'BIGINT',
  'DATE',
  'TIME',
  'TIMESTAMP',
  'INDICATOR',
]);
export type ParameterType = z.infer<typeof ParameterType>;

export const ParameterDefSchema = z
  .object({
    name: z.string().min(1),
    source: ParameterSource.optional(),
    field: z.string().min(1).optional(),
    type: ParameterType,
    length: z.number().int().positive().optional(),
    decimals: z.number().int().nonnegative().optional(),
    direction: ParameterDirection.default('IN'),
    required: z.boolean().default(true),
    default: z.unknown().optional(),
    as: z.string().min(1).optional(),
  })
  .superRefine((value, ctx) => {
    if ((value.direction === 'IN' || value.direction === 'INOUT') && !value.source) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: `parameter "${value.name}" has direction ${value.direction} and must declare a source`,
        path: ['source'],
      });
    }
    if ((value.type === 'CHAR' || value.type === 'VARCHAR') && !value.length) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: `parameter "${value.name}" of type ${value.type} must declare a length`,
        path: ['length'],
      });
    }
    if ((value.type === 'DECIMAL' || value.type === 'NUMERIC') && !value.length) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: `parameter "${value.name}" of type ${value.type} must declare a length (precision)`,
        path: ['length'],
      });
    }
  });
export type ParameterDef = z.infer<typeof ParameterDefSchema>;

export const HttpMethod = z.enum(['GET', 'POST', 'PUT', 'PATCH', 'DELETE']);
export type HttpMethod = z.infer<typeof HttpMethod>;

export const RouteDefSchema = z.object({
  name: z.string().min(1).optional(),
  method: HttpMethod,
  path: z.string().min(1),
  library: z.string().min(1),
  program: z.string().min(1),
  procedure: z.string().min(1).optional(),
  parameters: z.array(ParameterDefSchema).default([]),
  successStatus: z.number().int().min(100).max(599).default(200),
});
export type RouteDef = z.infer<typeof RouteDefSchema>;

export const RouteConfigSchema = z.object({
  routes: z.array(RouteDefSchema).min(1),
});
export type RouteConfig = z.infer<typeof RouteConfigSchema>;
