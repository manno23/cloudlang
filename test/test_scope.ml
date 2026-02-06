let run () =
  let program = Fixture.build_kv_store_ast () in
  let analysis = Fixture.analyze_exn program in

  assert (List.length analysis.module_vars = 6);

  let get_var name =
    List.find
      (fun (v : Cloudlang.Scope.var_info) -> v.name = name)
      analysis.module_vars
  in
  assert (get_var "store").is_mutable_state;
  assert (get_var "cache").is_mutable_state;
  assert (not (get_var "put").is_mutable_state);
  assert (get_var "put").is_function;
  assert (get_var "get").is_function;
  assert (get_var "cachedGet").is_function;
  assert (get_var "handleRequest").is_function;

  assert (List.length analysis.closures = 4);

  let get_closure name =
    List.find
      (fun (c : Cloudlang.Scope.closure_info) -> c.name = name)
      analysis.closures
  in

  let c_put = get_closure "put" in
  assert (c_put.free_vars = [ "store" ]);
  assert (c_put.captures_mutable = [ "store" ]);
  assert (c_put.called_functions = []);

  let c_get = get_closure "get" in
  assert (c_get.free_vars = [ "store" ]);
  assert (c_get.captures_mutable = [ "store" ]);
  assert (c_get.called_functions = []);

  let c_cached = get_closure "cachedGet" in
  assert (List.mem "cache" c_cached.free_vars);
  assert (List.mem "get" c_cached.free_vars);
  assert (c_cached.captures_mutable = [ "cache" ]);
  assert (List.mem "get" c_cached.called_functions);

  let c_handle = get_closure "handleRequest" in
  assert (List.mem "cachedGet" c_handle.free_vars);
  assert (List.mem "put" c_handle.free_vars);
  assert (c_handle.captures_mutable = []);
  assert (List.mem "cachedGet" c_handle.called_functions);
  assert (List.mem "put" c_handle.called_functions);

  assert (analysis.exports = [ "handleRequest" ])
