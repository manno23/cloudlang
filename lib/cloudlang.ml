module Ast = Ast
module Ir = Ir
module Scope = Scope
module Decompose = Decompose

type error = string

(** Analyse a TypeScript AST and decompose it into Worker groups. *)
let analyze (program : Ast.node) : (Scope.analysis_result, error) result =
  try Ok (Scope.analyze program)
  with Failure msg -> Error (Printf.sprintf "analysis error: %s" msg)

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
        let kvs =
          List.filter_map
            (function
              | Ir.KVBinding _ as b -> Some (generate_binding_json b)
              | _ -> None)
            w.bindings
        in
        let d1s =
          List.filter_map
            (function
              | Ir.D1Binding _ as b -> Some (generate_binding_json b)
              | _ -> None)
            w.bindings
        in
        let r2s =
          List.filter_map
            (function
              | Ir.R2Binding _ as b -> Some (generate_binding_json b)
              | _ -> None)
            w.bindings
        in
        let svcs =
          List.filter_map
            (function
              | Ir.ServiceBinding _ as b -> Some (generate_binding_json b)
              | _ -> None)
            w.bindings
        in
        (if kvs = [] then ""
         else
           Printf.sprintf
             {|,
  "kv_namespaces": [
%s
  ]|}
             (String.concat ",\n" kvs))
        ^ (if d1s = [] then ""
           else
             Printf.sprintf
               {|,
  "d1_databases": [
%s
  ]|}
               (String.concat ",\n" d1s))
        ^ (if r2s = [] then ""
           else
             Printf.sprintf
               {|,
  "r2_buckets": [
%s
  ]|}
               (String.concat ",\n" r2s))
        ^ (if svcs = [] then ""
           else
             Printf.sprintf
               {|,
  "services": [
%s
  ]|}
               (String.concat ",\n" svcs))
    in
    let routes_json =
      if w.routes = [] then ""
      else
        Printf.sprintf
          {|,
  "routes": [%s]|}
          (String.concat ", "
             (List.map (Printf.sprintf {|"%s"|}) w.routes))
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
    Printf.sprintf "--- Durable Object: %s ---\nScript: %s\n"
      dobj.class_name dobj.script

let generate (config : Ir.config) : string =
  if config = [] then "{}"
  else String.concat "\n" (List.map generate_resource config)
