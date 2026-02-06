# Example: Closure capturing a D1 resource -> Worker with D1 binding
#
# This demonstrates the core CloudLang transformation:
#   1. A D1 database resource is defined via the `d1` primitive
#   2. A closure (lambda) captures that resource as a free variable
#   3. The compiler detects the capture and generates:
#      - A D1Database IR resource
#      - A Worker IR resource with a D1 binding in its env
#      - TypeScript Worker script that accesses env.USERS_DB
#   4. Exporting the closure attaches a route to the Worker

define users_db = d1 "users-db" "CREATE TABLE users (id INT, name TEXT)"

define get_user = \id : string ->
  query users_db "SELECT * FROM users WHERE id = ?" id

export get_user
