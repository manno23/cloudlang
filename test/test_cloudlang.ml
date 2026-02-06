let () =
  print_endline "Running CloudLang tests...";

  Test_scope.run ();
  print_endline "  scope analysis: OK";

  Test_decompose.run ();
  print_endline "  decomposition: OK";

  Test_ir.run ();
  print_endline "  IR output: OK";

  Test_generate.run ();
  print_endline "  generated output: OK";

  print_endline "";
  print_endline "All tests passed!"
