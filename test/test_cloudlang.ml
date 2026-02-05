let test_ast_construction () =
  let loc = Cloudlang.Ast.{ line = 1; column = 1 } in
  let expr = Cloudlang.Ast.Int (42, loc) in
  match expr with
  | Cloudlang.Ast.Int (n, _) -> assert (n = 42)
  | _ -> assert false

let test_ir_construction () =
  let worker = Cloudlang.Ir.{ 
    name = "test-worker"; 
    script = "export default {}";
    routes = ["example.com/*"]
  } in
  assert (worker.name = "test-worker")

let test_parse () =
  match Cloudlang.parse "some source" with
  | Ok prog -> assert (prog = [])
  | Error _ -> assert false

let test_generate () =
  let output = Cloudlang.generate [] in
  assert (output = "{}")

let () =
  test_ast_construction ();
  test_ir_construction ();
  test_parse ();
  test_generate ();
  print_endline "All tests passed!"
