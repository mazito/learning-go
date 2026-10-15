# DRAFT.md

A "rough" spec for the SQL-connector-API (scapi)

The API exposes a set of predefined queries and actions on a "local" server 
(the place where the API is running) that are available to any connector that 
needs to use it to upload/download lists and records from/to the local sql 
engine to/from Treme.io.  

~~~
[ local sql engine | sql-connector-api ] << internet >> [ treme-connector ]
~~~

Connections are ALWAYS started by the API to a remote server (usually a Treme.io 
connector), which then establishes a bidirectional communication between the API
and the server. This avoids opening ports on the place where the API is running.

## Available methods list 

The API exposes a file with the enabled methods so they can be discovered, and 
also includes some additional definitions used by the methods, like a pool of 
available connections.

Enabled methods file `methods.enabled.toml`:
~~~ini
# File "methods.enabled.toml"
title = "All JSONRPC enabled methods"
describe = "List of available methods"

[[connection]]
pool = "pool01mssql2022"
server='localhost\mssql2022'  # or server='hostname\\instance' or 'host:port'
user='$ENV:SQL_USER'
password='$ENV:SQL_PASSW'
database='database02'
port = 1433  # optional, defaults to 1433

[[connection]]
pool = "pool02mssql2014"
server = 'localhost\mssql2014'  
user ='$ENV:SQL_USER'
password = '$ENV:SQL_PASSW'
database = 'database02'
port = 1433

[[method]]
name = "get_clients"
pool = "pool01mssql2022"
describe = "Retrieves a client list using a search param and filters"

[[method]]
name = "patch_client"
pool = "pool01mssql2022"
describe = "Updates a client with partial props"
~~~

## Method signatures

The API uses a JSON-RPC v2 for its query and action methods, and NEVER allows
direct SQL statements in any method.

A given method is defined by a .toml file that defines its input params,
the expected results, and the query/procedures to execute on the API side.

For a query, we may have a file `get_clients.method.toml` like this:
~~~ini
# File "get_clients.method.toml"
title = "Get clients" 
method = "get_clients"
describe = "Retrieves a client list using a search param and filters"

[params]
q = { type = "string", required = false, describe = "Search using one or more words" } 
filters = { required = false, describe = "Filters we can apply to the query",
  conditions = [{ 
    col = { type = "string" }, 
    values = { type = "string" }, 
    operator = { type = "EQ | NEQ | GT | GTE | LT | LTE | IN | NOT | IS NULL" },
  }] 
}  
orders = { required = false, describe = "How do we order it",
  by = [{ 
    col = { type = "string" }, 
    order = { type = "asc | desc" }
  }] 
}
start = { type = "integer", required = false, default = 0, describe = "Start at row N" }
limit = { type = "integer", required = false, default = 1000, describe = "Max number of rows" }

[results]
count = { type = "integer" }
clients = [{ 
  id = { type = "integer" }, 
  full_name = { type = "string" }, 
  uid = { type = "uidv7" }, 
  address = { type = "string" }, 
  notes = { type = "text" }
}]

[errors]
NOT_FOUND = "Client list does not exist"
BAD_REQUEST = "Bad params for request" 

[query]
sql = """
	SELECT ${expand_columns(:results.clients)} 
  FROM clients
  ${expand_conditions(:params.filters.conditions)}
  ${expand_search(:params.q, 'full_name,address,notes')}
  ${expand_order_by(:params.orders.by)} 
  ${expand_limits(:params.limit, :params.start)}
"""
~~~

For an update query, we may have a file `patch_client.method.toml` like this:
~~~ini
# File "patch_client.method.toml"
title = "Update a given client" 
method = "patch_client"
describe = "Updates a client with partial props"

[params]
uid = { type = "uidv7", required = true }
vrs = { type = "integer" }
client = { 
  # because this is a "patch" all table props are optional
  # so we may do a partial update to only some of them
  id = { type = "integer" },
  full_name = { type = "string" }, 
  uid = { type = "uidv7" }, 
  address = { type = "string" }, 
  notes = { type = "text" }
}

[results]
success = { type = "boolean" }
client = { 
  id = { type = "integer" }, 
  full_name = { type = "string" }, 
  uid = { type = "uidv7" }, 
  address = { type = "string" }, 
  notes = { type = "text" }
}

[errors]
NOT_FOUND = "Client does not exist"
BAD_REQUEST = "Bad params on request" 

[exec]
sql = """
	UPDATE clients
  SET ${expand_set_values(:params.client)}
  WHERE uid = :params.uid 
"""
~~~

## TO BE DONE

How do we define a method that touches many tables in full transaction , for example an invoce having invoice header, detail lines and a summary ? 

- One 'exec' per table ? How ? does not seem so easy to define ...
- We would need a way to indicate that some sql depends on a given params property items, or can we infer them from the params we give in the ${expand_...} functions ?

~~~
[params]
uid = { type = "uidv7", required = true }
vrs = { type = "integer" }
model = "Invoice.v1"
invoice = {
  id = { type = "integer" }, 
  client_name = { type = "string" }, 
  address = { type = "string" }, 
  notes = { type = "text" }
}
items = [{ 
  id = { type = "integer" },
  invoice_id = { type = "integer" },
  description = { type = "string" }, 
  price = { type = "double" }, 
  quantity = { type = "integer" }, 
  total = { type = "double" }
}]
summary = { 
  id = { type = "integer" },
  invoice_id = { type = "integer" },
  total = { type = "double" }
}

[[exec]]
sql = """
	UPDATE invoice
  SET ${expand_set_values(:params.invoice)}
  WHERE uid = :params.uid 
"""

[[exec]]
# bulk patch of the details: ONE statement for ALL items (JOIN form).
# v = derived table built from :params.items; expand_value_rows emits one
# (?, ..., ?) tuple per item, all bound. The alias list v(...) must match
# the items row schema: (id, invoice_id, description, price, quantity, total).
sql = """
	UPDATE d
  SET 
    d.description = v.description, d.price = v.price, d.quantity = v.quantity, d.total = v.total
  FROM details AS d
  JOIN 
    (VALUES ${expand_value_rows(:params.items)}) 
    AS v(id, invoice_id, description, price, quantity, total)
    ON v.id = d.id
  WHERE d.invoice_id = :params.invoice.id
"""

[[exec]]
sql = """
	UPDATE summary
  SET ${expand_set_values(:params.summary)}
  WHERE summary.invoice_id = :params.invoice.id AND summary.id = :params.summary.id 
"""
~~~

But does not seem very explicit ...

## Interpolation functions

They build a SQL statement fragment from some given params.

The `sql` template is plain SQL plus placeholders in two styles:

- `${fn(...)}` — an interpolation function call; replaced by the SQL
  fragment the function emits (which may be an empty string).
- `:params.x` / `:results.x` — a reference to a param value or a result
  schema. Values are always **bound** as query parameters, never
  string-concatenated, to avoid SQL injection. Structural tokens (column
  names, operators, sort directions) cannot be bound, so they are
  whitelist-validated against the row schema and the operator enum before
  being inlined. If several `WHERE`-side fragments appear in one template,
  they are joined with `AND`, and `WHERE` is emitted only when any of them
  is non-empty.

### expand_columns(columns)

Emits the `SELECT` column list for a query.

- signature: `expand_columns(columns: row_schema) → fragment`
- `columns` : `row_schema` — a `[results]` row schema, e.g. `:results.clients`.
- emits one `column AS property` item per declared field of the schema.
- unknown columns fail at load time.

### expand_conditions(conditions)

Emits a `WHERE`-side fragment for the filters.

- signature: `expand_conditions(conditions: condition[]) → fragment`
- `conditions` : array of `condition` objects —
  - `col` : `string` — must be a row-schema column.
  - `values` : `string` — one value for scalar operators, a
    comma-separated list for `IN`/`NOT`, empty for `IS NULL`.
  - `operator` : `"EQ | NEQ | GT | GTE | LT | LTE | IN | NOT | IS NULL"`.
- conditions are joined with `AND`; emitted values are bound as parameters.
- missing or empty input → empty string.

### expand_search(q, columns)

Emits a `WHERE`-side fragment for the free-text `q` search; joined to
`expand_conditions` output with `AND`.

- signature: `expand_search(q: string, columns: string) → fragment`
- `q` : `string` — one or more space-separated words, e.g. `:params.q`.
- `columns` : `string` — a literal, comma-separated list of column names,
  e.g. `'full_name,address,notes'`; every name must exist in the row schema.
- emits one group per word, columns inside the group with `OR`, words
  combined with `AND`; every word is a bound `LIKE` parameter.
- missing or empty `q` → empty string.

### expand_order_by(orders_by)

Emits the `ORDER BY` clause.

- signature: `expand_order_by(orders_by: order_by[]) → fragment`
- `orders_by` : array of `order_by` objects `{ col: string,
  order: "asc | desc" }`.
- `col` must exist in the row schema; `order` is whitelist-validated and
  inlined (sort directions cannot be bound as parameters).
- missing or empty input → `ORDER BY id ASC` (first row-schema column):
  paging requires an `ORDER BY` in the final statement.

### expand_set_values(set_values)

Emits the `SET` clause for a patch (`exec`).

- signature: `expand_set_values(set_values: patch_object) → fragment`
- `set_values` : object with any subset of the row-schema keys, each value
  typed as declared in the schema, e.g. `:params.client`.
- emits only the keys present in the request: `SET full_name = ?, notes = ?`.
- skips `uid` (it belongs to the `WHERE`); unknown keys fail validation.

### expand_limits(limit, start)

Emits the paging clause for the engine dialect.

- signature: `expand_limits(limit: integer = 1000,
  start: integer = 0) → fragment`
- `limit` : `integer` — max rows to return.
- `start` : `integer` — rows to skip.
- MSSQL dialect example: `OFFSET ? ROWS FETCH NEXT ? ROWS ONLY`; both
  values are bound as parameters, never inlined.
- the final statement must contain an `ORDER BY` — pairs with the
  `expand_order_by` default when no orders are given.

### `expand_value_rows(values)`

Emits the row tuples of a `(VALUES ...)` derived table, for bulk DML:
`UPDATE <a> SET <a>.c = v.c ... FROM <table> AS a JOIN (VALUES ...) AS v(...) ON ...`.

- signature: `expand_value_rows(values: row[]) → fragment`
- `values` : `row[]` — array of params whose row schema declares the fields,
  e.g. `:params.items`; tuple order = schema field order.
- emits one `(?, ?, ...)` per element, one **bound** placeholder per field;
  never inlines literals.
- the derived-table alias list `AS v(col, ...)` in the template must list
  exactly the same fields, in the same order, or load fails.
- empty array → `BAD_REQUEST` at runtime (nothing to update; an empty
  `(VALUES ...)` would be invalid SQL anyway).
