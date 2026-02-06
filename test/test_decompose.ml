let run () =
  let program = Fixture.build_kv_store_ast () in
  let analysis = Fixture.analyze_exn program in
  let groups = Cloudlang.Decompose.decompose analysis in

  assert (List.length groups = 3);

  let get_group name =
    List.find
      (fun (g : Cloudlang.Decompose.worker_group) -> g.name = name)
      groups
  in

  let g_storage = get_group "storage" in
  assert (List.mem "put" g_storage.functions);
  assert (List.mem "get" g_storage.functions);
  assert (g_storage.owned_state = [ "store" ]);
  assert (g_storage.service_deps = []);

  let g_cache = get_group "cache" in
  assert (g_cache.functions = [ "cachedGet" ]);
  assert (g_cache.owned_state = [ "cache" ]);
  assert (List.mem "storage" g_cache.service_deps);

  let g_api = get_group "handleRequest" in
  assert (g_api.functions = [ "handleRequest" ]);
  assert (g_api.owned_state = []);
  assert (List.mem "cache" g_api.service_deps);
  assert (List.mem "storage" g_api.service_deps)
