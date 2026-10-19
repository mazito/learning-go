# Complex obj retrieval

This example describes a method that retrieves a complex object: 

The returned obj is and Invoice composed of:

- Invoice Header: single obj that identifies the invoice like number, etc.
- Cliente Data: single obj that describes the invoiced cliente 
- Detail Items: an array of items related to this particular invoice
- Invoice Summary: as single obj final summary with total amount, taxes, etc.

~~~toml
method      = "get_invoice"
title       = "Get a particular invoice by its uid"
description = "Full invoice with header, client, items and summary"
version     = 1

# The list of required and optional params and its types
[params.schema]
uid = { type = "uuid", required = true }
vrs = { type = "integer", default = 1 }

[result.schema]
count = { type = "integer" }
header = {
  uid       = { type = "uuid" }
  id        = { type = "integer" }
  vrs       = { type = "integer", default = 1 }
  num       = { type = "string" }
  notes     = { type = "text" }
}
client = {
  id        = { type = "integer" }
  full_name = { type = "string" }
  address   = { type = "string" }
  notes     = { type = "text" }
}
details = [{
  id          = { type = "integer" }
  description = { type = "string" }
  quantity    = { type = "integer" }
  price       = { type = "double" }
  subtotal    = { type = "double" }
}]
summary = {
  id      = { type = "integer" }
  total   = { type = "string" }
}

[errors]
NOT_FOUND = "Invoice :params.uid not found"
BAD_REQUEST = "Bad params for request"

[[step]]
query = "_invoice" # we will get the 'invoice' obj in the 'bag'
returns = { type = "object", single = true }
sql = """
  SELECT * 
  FROM invoices 
  WHERE uid = :params.uid
"""

[[step]]
query = "_client"
returns = { type = "object", single = true }
sql = """
  SELECT * 
  FROM client 
  WHERE id = :invoice_obj.client_id
"""

[[step]]
query = "_items"
returns = { type = "array", min = 0, max = 500 }
sql = """
  SELECT uid, id, description, quantity, price, subtotal, invoice_id
  FROM invoice_items 
  WHERE invoice_id = :invoice_obj.id
"""

[[step]]
query = "_summary"
returns = { type = "object", single = true }
sql = """
  SELECT *  
  FROM invoice_totals 
  WHERE invoice_id = :invoice_obj.id
"""

[[step]]
emit = "result"
returns = {
  type = "object", single = true, 
  count   = 1,
  # here we map the query results to the constrained returned results
  header  = { from: "_invoice", schema: "result.schema.header"}
  client  = { from: "_client", schema: "result.schema.client"}
  details = { from: "_items", schema: "result.schema.details"}
  summary = { from: "_summary", schema: "result.schema.summary"}
}
~~~
