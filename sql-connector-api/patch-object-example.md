# Complex obj update

This example describes a method that updates a complex object, where 
all steps are exceuted inside a transaction.

Taken from DRAFT-v3.md.

~~~toml
method      = "patch_invoice"
title       = "Patch an invoice"
description = "Header + lines + summary in one transaction (fixed order: header, lines, summary)"
version     = 1

[params]
uid = { type = "uuid", required = true }
vrs = { type = "integer", required = true }

[params.invoice]
type     = "object"
required = true
[params.invoice.fields]
id          = { type = "integer", required = true }
client_name = { type = "string" }
address     = { type = "string" }
notes       = { type = "text" }

[params.items]
type = "array"
max  = 500
[params.items.fields]
id          = { type = "integer", required = true }
description = { type = "string" }
price       = { type = "double" }
quantity    = { type = "integer" }
total       = { type = "double" }

[params.summary]
type = "object"
[params.summary.fields]
id    = { type = "integer", required = true }
total = { type = "double" }

[results.invoice]
type = "object"
[results.invoice.fields]
id          = { type = "integer" }
uid         = { type = "uuid" }
vrs         = { type = "integer" }
client_name = { type = "string" }
address     = { type = "string" }
notes       = { type = "text" }

[results.items]
type = "array"
[results.items.fields]
id          = { type = "integer" }
description = { type = "string" }
price       = { type = "double" }
quantity    = { type = "integer" }
total       = { type = "double" }

[errors]
NOT_FOUND = "Invoice does not exist"
CONFLICT  = "Invoice was modified by someone else"

[[step]]
exec    = "header"
expect  = "one"
on_zero = "CONFLICT"
sql = """
  UPDATE invoice
  SET ${expand_set(:params.invoice, "invoice")}, vrs = vrs + 1
  WHERE uid = :params.uid AND vrs = :params.vrs
"""

[[step]]
exec    = "lines"
foreach = ":params.items"
expect  = "one"
sql = """
  UPDATE details
  SET ${expand_set(:item, "details")}
  WHERE id = :item.id AND invoice_id = :params.invoice.id
"""

[[step]]
exec   = "summary"
when   = ":params.summary"
expect = "one"
sql = """
  UPDATE summary
  SET ${expand_set(:params.summary, "summary")}
  WHERE invoice_id = :params.invoice.id AND id = :params.summary.id
"""

[[step]]
query = "invoice"
sql = "SELECT ${expand_columns(\"invoice\", @results.invoice)} FROM invoice WHERE uid = :params.uid"

[[step]]
query = "items"
sql = "SELECT ${expand_columns(\"details\", @results.items)} FROM details WHERE invoice_id = :params.invoice.id ORDER BY id"

[[step]]
emit = "results"
[step.fields]
invoice = { from = "invoice", one = true }
items   = "items"
~~~



