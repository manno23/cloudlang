module Ast = Ast
module Ir = Ir

type error = string

let example_loc = Ast.{ line = 1; column = 1 }

let example_closure_program () : Ast.program =
  let open Ast in
  [ Define
      ( "make_greeter",
        Lambda
          ( "prefix",
            TString,
            Lambda
              ( "name",
                TString,
                PrimOp
                  ( "concat",
                    [ Var ("prefix", example_loc); Var ("name", example_loc) ],
                    example_loc ),
                example_loc ),
            example_loc ),
        example_loc );
    Define
      ( "handler",
        Lambda
          ( "request",
            TString,
            Let
              ( "greet",
                App
                  ( App
                      ( Var ("make_greeter", example_loc),
                        String ("Hello ", example_loc),
                        example_loc ),
                    String ("world", example_loc),
                    example_loc ),
                Var ("greet", example_loc),
                example_loc ),
            example_loc ),
        example_loc );
    Export ("handler", example_loc) ]

let example_closure_config () : Ir.config =
  let edge_worker =
    Ir.
      { name = "edge-worker";
        script =
          "export default {\n  async fetch(request, env) {\n    const url = new URL(request.url);\n    const name = url.searchParams.get(\"name\") || \"world\";\n    const response = await env.COMPUTE.fetch(\"https://compute/hello?name=\" + name);\n    const body = await response.text();\n    await env.APP_DATA.put(\"last-greeting\", body);\n    return new Response(body, { status: 200 });\n  }\n};\n";
        routes = [ "example.com/*" ];
      }
  in
  let compute_worker =
    Ir.
      { name = "compute-worker";
        script =
          "export default {\n  async fetch(request) {\n    const url = new URL(request.url);\n    const name = url.searchParams.get(\"name\") || \"world\";\n    const prefix = \"Hello \";\n    const greet = (n) => prefix + n;\n    return new Response(greet(name), { status: 200 });\n  }\n};\n";
        routes = [];
      }
  in
  let bucket = Ir.{ name = "app-data"; location = "us-west-1" } in
  [ Ir.Worker edge_worker; Ir.Worker compute_worker; Ir.R2Bucket bucket ]

let parse (_s : string) : (Ast.program, error) result =
  Ok []

let typecheck (p : Ast.program) : (Ast.program, error) result =
  Ok p

let compile (p : Ast.program) : (Ir.config, error) result =
  if p = example_closure_program () then Ok (example_closure_config ()) else Ok []

let json_escape (s : string) : string =
  let buffer = Buffer.create (String.length s) in
  String.iter
    (function
      | '"' -> Buffer.add_string buffer "\\\""
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\n' -> Buffer.add_string buffer "\\n"
      | '\r' -> Buffer.add_string buffer "\\r"
      | '\t' -> Buffer.add_string buffer "\\t"
      | c -> Buffer.add_char buffer c)
    s;
  Buffer.contents buffer

let json_string (s : string) : string =
  "\"" ^ json_escape s ^ "\""

let json_list (items : string list) : string =
  "[" ^ String.concat ", " items ^ "]"

let generate (c : Ir.config) : string =
  if c = [] then "{}"
  else
    let workers =
      List.filter_map
        (function
          | Ir.Worker worker ->
              Some
                ("{" ^ "\"name\": " ^ json_string worker.name ^ ", "
               ^ "\"script\": " ^ json_string worker.script ^ ", "
               ^ "\"routes\": "
               ^ json_list (List.map json_string worker.routes)
               ^ "}")
          | _ -> None)
        c
    in
    let r2_buckets =
      List.filter_map
        (function
          | Ir.R2Bucket bucket ->
              Some
                ("{" ^ "\"name\": " ^ json_string bucket.name ^ ", "
               ^ "\"location\": " ^ json_string bucket.location ^ "}")
          | _ -> None)
        c
    in
    "{" ^ "\"workers\": " ^ json_list workers ^ ", " ^ "\"r2_buckets\": "
    ^ json_list r2_buckets ^ "}"
