(* ================================================================== *)
(* CloudLang test: TypeScript kv-store -> Cloudflare Worker topology  *)
(* ================================================================== *)
(*
 * TypeScript source (examples/kv-store.ts):
 *
 *   const store = new Map<string, string>();
 *
 *   const put = (key: string, value: string): void => {
 *     store.set(key, value);
 *   };
 *
 *   const get = (key: string): string | undefined => {
 *     return store.get(key);
 *   };
 *
 *   const cache = new Map<string, string>();
 *
 *   const cachedGet = (key: string): string | undefined => {
 *     const hit = cache.get(key);
 *     if (hit) return hit;
 *     const result = get(key);
 *     if (result) {
 *       cache.set(key, result);
 *       return result;
 *     }
 *     return undefined;
 *   };
 *
 *   const handleRequest = (method: string, key: string, value?: string): string => {
 *     if (method === "GET") {
 *       return cachedGet(key) ?? "NOT_FOUND";
 *     }
 *     if (method === "PUT" && value) {
 *       put(key, value);
 *       return "OK";
 *     }
 *     return "BAD_REQUEST";
 *   };
 *
 *   export { handleRequest };
 *
 * Expected decomposition:
 *   1. Worker "storage" — contains put, get; KV binding for store
 *   2. Worker "cache"   — contains cachedGet; KV binding for cache,
 *                         service binding to storage
 *   3. Worker "handleRequest" — contains handleRequest; service bindings
 *                               to cache and storage; route /handleRequest
 *)

(** Convenience alias. *)
module A = Cloudlang.Ast

(** Substring test helper. *)
let has_substr s sub =
  let len_s = String.length s in
  let len_sub = String.length sub in
  if len_sub > len_s then false
  else
    let found = ref false in
    for i = 0 to len_s - len_sub do
      if String.sub s i len_sub = sub then found := true
    done;
    !found

(* ------------------------------------------------------------------ *)
(* AST helpers — shorthand constructors for readability                *)
(* ------------------------------------------------------------------ *)

let id name = A.Identifier { name }
let str s = A.Literal { value = A.LString s }
let undef = A.Literal { value = A.LUndefined }

let const_decl name init =
  A.VariableDeclaration
    {
      kind = A.Const;
      declarations = [ A.VariableDeclarator { id = id name; init } ];
    }

let arrow params body =
  A.ArrowFunctionExpression { params; body; async_ = false }

let call callee arguments = A.CallExpression { callee; arguments }
let member obj prop = A.MemberExpression { object_ = obj; property = id prop }
let expr_stmt e = A.ExpressionStatement { expression = e }
let block stmts = A.BlockStatement { body = stmts }
let ret e = A.ReturnStatement { argument = Some e }
let ret_void = A.ReturnStatement { argument = None }
let _ = ret_void (* suppress unused warning *)

let if_ test consequent alternate =
  A.IfStatement { test; consequent; alternate }

let bin op left right = A.BinaryExpression { operator = op; left; right }

let logic op left right =
  A.LogicalExpression { operator = op; left; right }

let new_ callee arguments = A.NewExpression { callee; arguments }

let export_named names =
  A.ExportNamedDeclaration
    {
      specifiers =
        List.map (fun n -> A.ExportSpecifier { local = id n }) names;
    }

(* ------------------------------------------------------------------ *)
(* Build the kv-store AST                                              *)
(* ------------------------------------------------------------------ *)

let build_kv_store_ast () : A.node =
  A.Program
    {
      body =
        [
          (* const store = new Map(); *)
          const_decl "store" (Some (new_ (id "Map") []));
          (* const put = (key, value) => { store.set(key, value); }; *)
          const_decl "put"
            (Some
               (arrow [ id "key"; id "value" ]
                  (block
                     [
                       expr_stmt
                         (call (member (id "store") "set")
                            [ id "key"; id "value" ]);
                     ])));
          (* const get = (key) => { return store.get(key); }; *)
          const_decl "get"
            (Some
               (arrow [ id "key" ]
                  (block
                     [
                       ret
                         (call (member (id "store") "get") [ id "key" ]);
                     ])));
          (* const cache = new Map(); *)
          const_decl "cache" (Some (new_ (id "Map") []));
          (* const cachedGet = (key) => {
               const hit = cache.get(key);
               if (hit) return hit;
               const result = get(key);
               if (result) { cache.set(key, result); return result; }
               return undefined;
             }; *)
          const_decl "cachedGet"
            (Some
               (arrow [ id "key" ]
                  (block
                     [
                       const_decl "hit"
                         (Some
                            (call (member (id "cache") "get") [ id "key" ]));
                       if_ (id "hit") (ret (id "hit")) None;
                       const_decl "result"
                         (Some (call (id "get") [ id "key" ]));
                       if_ (id "result")
                         (block
                            [
                              expr_stmt
                                (call (member (id "cache") "set")
                                   [ id "key"; id "result" ]);
                              ret (id "result");
                            ])
                         None;
                       ret undef;
                     ])));
          (* const handleRequest = (method, key, value) => {
               if (method === "GET") {
                 return cachedGet(key) ?? "NOT_FOUND";
               }
               if (method === "PUT" && value) {
                 put(key, value);
                 return "OK";
               }
               return "BAD_REQUEST";
             }; *)
          const_decl "handleRequest"
            (Some
               (arrow [ id "method"; id "key"; id "value" ]
                  (block
                     [
                       if_
                         (bin "===" (id "method") (str "GET"))
                         (ret
                            (logic "??"
                               (call (id "cachedGet") [ id "key" ])
                               (str "NOT_FOUND")))
                         None;
                       if_
                         (logic "&&"
                            (bin "===" (id "method") (str "PUT"))
                            (id "value"))
                         (block
                            [
                              expr_stmt
                                (call (id "put") [ id "key"; id "value" ]);
                              ret (str "OK");
                            ])
                         None;
                       ret (str "BAD_REQUEST");
                     ])));
          (* export { handleRequest }; *)
          export_named [ "handleRequest" ];
        ];
    }

(* ================================================================== *)
(* Test 1: Scope analysis                                              *)
(* ================================================================== *)

let test_scope_analysis () =
  let program = build_kv_store_ast () in
  let analysis =
    match Cloudlang.analyze program with
    | Ok a -> a
    | Error e -> failwith (Printf.sprintf "analyze failed: %s" e)
  in

  (* Should find 6 module-scope declarations:
     store (mutable), put (fn), get (fn), cache (mutable),
     cachedGet (fn), handleRequest (fn) *)
  assert (List.length analysis.module_vars = 6);

  (* Check mutable state detection *)
  let find_var name =
    List.find
      (fun (v : Cloudlang.Scope.var_info) -> v.name = name)
      analysis.module_vars
  in
  assert (find_var "store").is_mutable_state;
  assert (find_var "cache").is_mutable_state;
  assert (not (find_var "put").is_mutable_state);
  assert (find_var "put").is_function;
  assert (find_var "get").is_function;
  assert (find_var "cachedGet").is_function;
  assert (find_var "handleRequest").is_function;

  (* Should find 4 closures *)
  assert (List.length analysis.closures = 4);

  let find_closure name =
    List.find
      (fun (c : Cloudlang.Scope.closure_info) -> c.name = name)
      analysis.closures
  in

  (* put: free_vars=[store], captures_mutable=[store], calls=[] *)
  let c_put = find_closure "put" in
  assert (c_put.free_vars = [ "store" ]);
  assert (c_put.captures_mutable = [ "store" ]);
  assert (c_put.called_functions = []);

  (* get: free_vars=[store], captures_mutable=[store], calls=[] *)
  let c_get = find_closure "get" in
  assert (c_get.free_vars = [ "store" ]);
  assert (c_get.captures_mutable = [ "store" ]);
  assert (c_get.called_functions = []);

  (* cachedGet: free_vars=[cache, get], captures_mutable=[cache],
                called_functions=[get] *)
  let c_cached = find_closure "cachedGet" in
  assert (List.mem "cache" c_cached.free_vars);
  assert (List.mem "get" c_cached.free_vars);
  assert (c_cached.captures_mutable = [ "cache" ]);
  assert (List.mem "get" c_cached.called_functions);

  (* handleRequest: free_vars=[cachedGet, put],
                    captures_mutable=[],
                    called_functions=[cachedGet, put] *)
  let c_handle = find_closure "handleRequest" in
  assert (List.mem "cachedGet" c_handle.free_vars);
  assert (List.mem "put" c_handle.free_vars);
  assert (c_handle.captures_mutable = []);
  assert (List.mem "cachedGet" c_handle.called_functions);
  assert (List.mem "put" c_handle.called_functions);

  (* Exports *)
  assert (analysis.exports = [ "handleRequest" ]);

  Printf.printf "  scope analysis: OK\n"

(* ================================================================== *)
(* Test 2: Decomposition into Worker groups                            *)
(* ================================================================== *)

let test_decomposition () =
  let program = build_kv_store_ast () in
  let analysis =
    match Cloudlang.analyze program with
    | Ok a -> a
    | Error e -> failwith (Printf.sprintf "analyze failed: %s" e)
  in
  let groups = Cloudlang.Decompose.decompose analysis in

  (* Should produce 3 groups *)
  assert (List.length groups = 3);

  let find_group name =
    List.find
      (fun (g : Cloudlang.Decompose.worker_group) -> g.name = name)
      groups
  in

  (* storage group: put + get, owns store *)
  let g_storage = find_group "storage" in
  assert (List.mem "put" g_storage.functions);
  assert (List.mem "get" g_storage.functions);
  assert (g_storage.owned_state = [ "store" ]);
  assert (g_storage.service_deps = []);

  (* cache group: cachedGet, owns cache, depends on storage *)
  let g_cache = find_group "cache" in
  assert (g_cache.functions = [ "cachedGet" ]);
  assert (g_cache.owned_state = [ "cache" ]);
  assert (List.mem "storage" g_cache.service_deps);

  (* handleRequest group: handleRequest, no state, depends on cache + storage *)
  let g_api = find_group "handleRequest" in
  assert (g_api.functions = [ "handleRequest" ]);
  assert (g_api.owned_state = []);
  assert (List.mem "cache" g_api.service_deps);
  assert (List.mem "storage" g_api.service_deps);

  Printf.printf "  decomposition: OK\n"

(* ================================================================== *)
(* Test 3: Full pipeline -> IR config                                  *)
(* ================================================================== *)

let test_ir_output () =
  let program = build_kv_store_ast () in
  let analysis =
    match Cloudlang.analyze program with
    | Ok a -> a
    | Error e -> failwith (Printf.sprintf "analyze failed: %s" e)
  in
  let config =
    match Cloudlang.compile analysis with
    | Ok c -> c
    | Error e -> failwith (Printf.sprintf "compile failed: %s" e)
  in

  (* Should produce 3 Workers *)
  assert (List.length config = 3);

  (* All resources should be Workers *)
  List.iter
    (function
      | Cloudlang.Ir.Worker _ -> ()
      | _ -> failwith "expected only Worker resources")
    config;

  let find_worker name =
    List.find_map
      (function
        | Cloudlang.Ir.Worker w when w.name = name -> Some w
        | _ -> None)
      config
    |> Option.get
  in

  (* storage Worker: KV binding for STORE, no service bindings, no routes *)
  let w_storage = find_worker "storage" in
  assert (
    List.exists
      (function
        | Cloudlang.Ir.KVBinding { name = "STORE"; namespace_id } ->
          namespace_id = "cloudlang-store"
        | _ -> false)
      w_storage.bindings);
  assert (w_storage.routes = []);

  (* cache Worker: KV binding for CACHE + service binding to storage *)
  let w_cache = find_worker "cache" in
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

  (* handleRequest Worker: service bindings to cache + storage, route *)
  let w_api = find_worker "handleRequest" in
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

  (* Worker scripts should have correct env types *)
  assert (has_substr w_storage.script "STORE: KVNamespace;");
  assert (has_substr w_cache.script "CACHE: KVNamespace;");
  assert (has_substr w_cache.script "STORAGE: Fetcher;");
  assert (has_substr w_api.script "CACHE: Fetcher;");
  assert (has_substr w_api.script "STORAGE: Fetcher;");

  Printf.printf "  IR output: OK\n"

(* ================================================================== *)
(* Test 4: Generated output strings                                    *)
(* ================================================================== *)

let test_generated_output () =
  let program = build_kv_store_ast () in
  let analysis =
    match Cloudlang.analyze program with
    | Ok a -> a
    | Error e -> failwith (Printf.sprintf "analyze failed: %s" e)
  in
  let config =
    match Cloudlang.compile analysis with
    | Ok c -> c
    | Error e -> failwith (Printf.sprintf "compile failed: %s" e)
  in
  let output = Cloudlang.generate config in

  (* Wrangler config assertions *)
  assert (has_substr output {|"name": "storage"|});
  assert (has_substr output {|"name": "cache"|});
  assert (has_substr output {|"name": "handleRequest"|});

  (* KV namespace bindings *)
  assert (has_substr output {|"binding": "STORE"|});
  assert (has_substr output {|"id": "cloudlang-store"|});
  assert (has_substr output {|"binding": "CACHE"|});
  assert (has_substr output {|"id": "cloudlang-cache"|});

  (* Service bindings *)
  assert (has_substr output {|"service": "storage"|});
  assert (has_substr output {|"service": "cache"|});

  (* Routes *)
  assert (has_substr output {|"/handleRequest"|});

  (* TypeScript script content *)
  assert (has_substr output "interface Env");
  assert (has_substr output "async fetch");
  assert (has_substr output "export default");

  Printf.printf "  generated output: OK\n";

  (* Print full output for visual inspection *)
  Printf.printf
    "\n\
     === Full Generated Output ===\n\n\
     %s\n"
    output

(* ================================================================== *)
(* Test runner                                                         *)
(* ================================================================== *)

let () =
  Printf.printf "Running CloudLang tests...\n";
  test_scope_analysis ();
  test_decomposition ();
  test_ir_output ();
  test_generated_output ();
  print_endline "\nAll tests passed!"
