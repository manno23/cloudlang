let get_worker name config =
  match
    List.find_map
      (function
        | Cloudlang.Ir.Worker w when w.name = name -> Some w | _ -> None)
      config
  with
  | Some w -> w
  | None -> failwith (Printf.sprintf "missing worker: %s" name)

let run () =
  let program = Fixture.build_kv_store_ast () in
  let analysis = Fixture.analyze_exn program in
  let config = Fixture.compile_exn analysis in

  assert (List.length config = 3);

  List.iter
    (function
      | Cloudlang.Ir.Worker _ -> ()
      | _ -> failwith "expected only Worker resources")
    config;

  let w_storage = get_worker "storage" config in
  assert (
    List.exists
      (function
        | Cloudlang.Ir.KVBinding { name = "STORE"; namespace_id } ->
            namespace_id = "cloudlang-store"
        | _ -> false)
      w_storage.bindings);
  assert (w_storage.routes = []);

  let w_cache = get_worker "cache" config in
  assert (
    List.exists
      (function
        | Cloudlang.Ir.KVBinding { name = "CACHE"; namespace_id } ->
            namespace_id = "cloudlang-cache"
        | _ -> false)
      w_cache.bindings);
  assert (
    List.exists
      (function
        | Cloudlang.Ir.ServiceBinding { name = "STORAGE"; service } ->
            service = "storage"
        | _ -> false)
      w_cache.bindings);
  assert (w_cache.routes = []);

  let w_api = get_worker "handleRequest" config in
  assert (
    List.exists
      (function
        | Cloudlang.Ir.ServiceBinding { name = "CACHE"; service } ->
            service = "cache"
        | _ -> false)
      w_api.bindings);
  assert (
    List.exists
      (function
        | Cloudlang.Ir.ServiceBinding { name = "STORAGE"; service } ->
            service = "storage"
        | _ -> false)
      w_api.bindings);
  assert (w_api.routes = [ "/handleRequest" ]);

  assert (Fixture.has_substr w_storage.script "STORE: KVNamespace;");
  assert (Fixture.has_substr w_cache.script "CACHE: KVNamespace;");
  assert (Fixture.has_substr w_cache.script "STORAGE: Fetcher;");
  assert (Fixture.has_substr w_api.script "CACHE: Fetcher;");
  assert (Fixture.has_substr w_api.script "STORAGE: Fetcher;")
