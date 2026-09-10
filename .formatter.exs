spark_locals_without_parens = [
  base_filter_sql: 1,
  engine: 1,
  migrate?: 1,
  migration_defaults: 1,
  options: 1,
  repo: 1,
  select: 1,
  source: 1,
  table: 1,
  to: 1
]

# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: spark_locals_without_parens,
  export: [locals_without_parens: spark_locals_without_parens]
]
