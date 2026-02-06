module Ast = Ast
module Ir = Ir
module Scope = Scope
module Decompose = Decompose

type error = string

(** Analyse a TypeScript AST and decompose it into Worker groups. *)
let analyze (program : Ast.node) : (Scope.analysis_result, error) result =
  Scope.analyze program
  |> Result.map_error (fun err ->
      Printf.sprintf "analysis error: %s" (Scope.error_to_string err))

(** Decompose analysis results into Worker groups and convert to IR. *)
let compile (analysis : Scope.analysis_result) : (Ir.config, error) result =
  let groups = Decompose.decompose analysis in
  Ok (Decompose.to_ir groups analysis)

(* --- Code generation: IR -> output string --- *)

(** Generate a JSON-style wrangler configuration for a binding. *)
let generate_binding_json (b : Ir.binding) : string =
  match b with
  | Ir.D1Binding { name; database_id } ->
      Printf.sprintf {|    { "binding": "%s", "database_id": "%s" }|} name
        database_id
  | Ir.KVBinding { name; namespace_id } ->
      Printf.sprintf {|    { "binding": "%s", "id": "%s" }|} name namespace_id
  | Ir.R2Binding { name; bucket_name } ->
      Printf.sprintf {|    { "binding": "%s", "bucket_name": "%s" }|} name
        bucket_name
  | Ir.ServiceBinding { name; service } ->
      Printf.sprintf {|    { "binding": "%s", "service": "%s" }|} name service

(** Generate output for a single resource. *)
let generate_resource (r : Ir.resource) : string =
  match r with
  | Ir.Worker w ->
      let bindings_json =
        if w.bindings = [] then ""
        else
          let section field lines =
            if lines = [] then ""
            else
              Printf.sprintf {|,
  "%s": [
%s
  ]|} field
                (String.concat ",\n" lines)
          in
          let kvs, d1s, r2s, svcs =
            List.fold_left
              (fun (kvs, d1s, r2s, svcs) b ->
                match b with
                | Ir.KVBinding _ ->
                    (generate_binding_json b :: kvs, d1s, r2s, svcs)
                | Ir.D1Binding _ ->
                    (kvs, generate_binding_json b :: d1s, r2s, svcs)
                | Ir.R2Binding _ ->
                    (kvs, d1s, generate_binding_json b :: r2s, svcs)
                | Ir.ServiceBinding _ ->
                    (kvs, d1s, r2s, generate_binding_json b :: svcs))
              ([], [], [], []) w.bindings
          in
          section "kv_namespaces" (List.rev kvs)
          ^ section "d1_databases" (List.rev d1s)
          ^ section "r2_buckets" (List.rev r2s)
          ^ section "services" (List.rev svcs)
      in
      let routes_json =
        if w.routes = [] then ""
        else
          Printf.sprintf {|,
  "routes": [%s]|}
            (String.concat ", " (List.map (Printf.sprintf {|"%s"|}) w.routes))
      in
      Printf.sprintf
        "--- Worker: %s ---\n\
         == wrangler.toml ==\n\
         {\n\
        \  \"name\": \"%s\"%s%s\n\
         }\n\n\
         == script ==\n\
         %s"
        w.name w.name bindings_json routes_json w.script
  | Ir.D1Database db ->
      Printf.sprintf "--- D1 Database: %s ---\nSchema: %s\n" db.name db.schema
  | Ir.R2Bucket bucket ->
      Printf.sprintf "--- R2 Bucket: %s ---\nLocation: %s\n" bucket.name
        bucket.location
  | Ir.DurableObject dobj ->
      Printf.sprintf "--- Durable Object: %s ---\nScript: %s\n" dobj.class_name
        dobj.script

let generate (config : Ir.config) : string =
  if config = [] then "{}"
  else String.concat "\n" (List.map generate_resource config)
