let test_ast_construction () =
  let loc = Cloudlang.Ast.{ line = 1; column = 1 } in
  let expr = Cloudlang.Ast.Int (42, loc) in
  match expr with
  | Cloudlang.Ast.Int (n, _) -> assert (n = 42)
  | _ -> assert false

let test_ir_construction () =
  let worker =
    Cloudlang.Ir.{ name = "test-worker"; script = "export default {}"; routes = [] }
  in
  assert (worker.name = "test-worker")

let test_parse () =
  match Cloudlang.parse "some source" with
  | Ok prog -> assert (prog = [])
  | Error _ -> assert false

let test_compile_example_closure () =
  let program = Cloudlang.example_closure_program () in
  let expected_config = Cloudlang.example_closure_config () in
  match Cloudlang.compile program with
  | Ok config -> assert (config = expected_config)
  | Error _ -> assert false

let test_generate_example_config () =
  let config = Cloudlang.example_closure_config () in
  let output = Cloudlang.generate config in
  let expected =
    "{" ^ "\"workers\": [" ^
    "{\"name\": \"edge-worker\", \"script\": \"export default {\\n  async fetch(request, env) {\\n    const url = new URL(request.url);\\n    const name = url.searchParams.get(\\\"name\\\") || \\\"world\\\";\\n    const response = await env.COMPUTE.fetch(\\\"https://compute/hello?name=\\\" + name);\\n    const body = await response.text();\\n    await env.APP_DATA.put(\\\"last-greeting\\\", body);\\n    return new Response(body, { status: 200 });\\n  }\\n};\\n\", \"routes\": [\"example.com/*\"]}, " ^
    "{\"name\": \"compute-worker\", \"script\": \"export default {\\n  async fetch(request) {\\n    const url = new URL(request.url);\\n    const name = url.searchParams.get(\\\"name\\\") || \\\"world\\\";\\n    const prefix = \\\"Hello \\\";\\n    const greet = (n) => prefix + n;\\n    return new Response(greet(name), { status: 200 });\\n  }\\n};\\n\", \"routes\": []}"
    ^ "], " ^ "\"r2_buckets\": "
    ^ "[{\"name\": \"app-data\", \"location\": \"us-west-1\"}]" ^ "}"
  in
  assert (output = expected)

let test_generate_empty_config () =
  let output = Cloudlang.generate [] in
  assert (output = "{}")

let () =
  test_ast_construction ();
  test_ir_construction ();
  test_parse ();
  test_compile_example_closure ();
  test_generate_example_config ();
  test_generate_empty_config ();
  print_endline "All tests passed!"
