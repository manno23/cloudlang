(** Closure decomposition: scope analysis -> Worker groups -> IR.

    Algorithm:
    1. Seed groups from mutable state: functions that capture the same
       mutable variable are placed in the same group.
    2. Remaining functions (no mutable captures) become their own group.
    3. Cross-group function calls become service binding dependencies.
    4. Convert groups to IR Workers with KV and service bindings. *)

type worker_group = {
  name : string;
  functions : string list;
  owned_state : string list;
  service_deps : string list;
}

(** Deduplicate a string list, preserving first-occurrence order. *)
let dedup xs =
  List.fold_left
    (fun acc x -> if List.mem x acc then acc else acc @ [ x ])
    [] xs

(** Find which group a function belongs to. *)
let group_of_function (groups : worker_group list) (fn_name : string) :
    string option =
  List.find_map
    (fun g ->
       if List.mem fn_name g.functions then Some g.name else None)
    groups

(** Derive a group name from the mutable state variable name.
    e.g. "store" -> "storage", "cache" -> "cache" *)
let group_name_of_state (state_var : string) : string =
  if state_var = "store" then "storage" else state_var

(** Decompose scope analysis results into Worker groups. *)
let decompose (analysis : Scope.analysis_result) : worker_group list =
  let closures = analysis.closures in

  (* Step 1: Build mutable-state -> functions mapping.
     Each mutable state variable seeds a group containing all functions
     that directly capture it. *)
  let all_mutable =
    dedup
      (List.concat_map
         (fun (c : Scope.closure_info) -> c.captures_mutable)
         closures)
  in
  let state_groups =
    List.map
      (fun state_var ->
         let fns =
           List.filter_map
             (fun (c : Scope.closure_info) ->
                if List.mem state_var c.captures_mutable then
                  Some c.name
                else None)
             closures
         in
         (state_var, dedup fns))
      all_mutable
  in
  (* Merge groups that share functions (i.e. a function captures
     multiple mutable state vars -> those vars' groups merge). *)
  let merged_groups : (string list * string list) list =
    List.fold_left
      (fun acc (state_var, fns) ->
         (* Find any existing merged group that shares a function *)
         let overlapping, rest =
           List.partition
             (fun (_states, group_fns) ->
                List.exists (fun f -> List.mem f group_fns) fns)
             acc
         in
         match overlapping with
         | [] -> ([ state_var ], fns) :: rest
         | _ ->
           let all_states =
             dedup
               ([ state_var ]
                @ List.concat_map fst overlapping)
           in
           let all_fns =
             dedup (fns @ List.concat_map snd overlapping)
           in
           (all_states, all_fns) :: rest)
      [] state_groups
  in
  let state_based_groups =
    List.map
      (fun (states, fns) ->
         let name =
           match states with
           | [ s ] -> group_name_of_state s
           | _ ->
             String.concat "_"
               (List.map group_name_of_state states)
         in
         { name; functions = fns; owned_state = states;
           service_deps = [] })
      merged_groups
  in
  (* Step 2: Functions with no mutable captures become their own group. *)
  let assigned_fns =
    List.concat_map (fun g -> g.functions) state_based_groups
  in
  let standalone_groups =
    List.filter_map
      (fun (c : Scope.closure_info) ->
         if List.mem c.name assigned_fns then None
         else
           Some
             { name = c.name;
               functions = [ c.name ];
               owned_state = [];
               service_deps = [] })
      closures
  in
  let all_groups = state_based_groups @ standalone_groups in
  (* Step 3: Compute cross-group service dependencies. *)
  List.map
    (fun group ->
       let deps =
         List.concat_map
           (fun fn_name ->
              match
                List.find_opt
                  (fun (c : Scope.closure_info) -> c.name = fn_name)
                  closures
              with
              | None -> []
              | Some closure ->
                List.filter_map
                  (fun called ->
                     match group_of_function all_groups called with
                     | Some target_group
                       when target_group <> group.name ->
                       Some target_group
                     | _ -> None)
                  closure.called_functions)
           group.functions
       in
       { group with service_deps = dedup deps })
    all_groups

(** Generate a TypeScript Worker script for a group. *)
let generate_worker_script (group : worker_group) : string =
  let env_types =
    List.map
      (fun state_var ->
         Printf.sprintf "  %s: KVNamespace;"
           (String.uppercase_ascii state_var))
      group.owned_state
    @ List.map
        (fun dep ->
           Printf.sprintf "  %s: Fetcher;"
             (String.uppercase_ascii dep))
        group.service_deps
  in
  let env_type_block =
    if env_types = [] then ""
    else
      Printf.sprintf "interface Env {\n%s\n}\n\n"
        (String.concat "\n" env_types)
  in
  let kv_access =
    List.map
      (fun state_var ->
         Printf.sprintf "  const %s = env.%s;" state_var
           (String.uppercase_ascii state_var))
      group.owned_state
  in
  let svc_access =
    List.map
      (fun dep ->
         Printf.sprintf "  const %s = env.%s;" dep
           (String.uppercase_ascii dep))
      group.service_deps
  in
  let body_lines =
    kv_access @ svc_access
    @ (if kv_access <> [] || svc_access <> [] then [ "" ] else [])
    @ List.map
        (fun fn_name ->
           Printf.sprintf "  // handler: %s" fn_name)
        group.functions
    @ [ "  return new Response(\"ok\");" ]
  in
  let env_param =
    if env_types = [] then "_env" else "env"
  in
  Printf.sprintf
    "%sexport default {\n\
    \  async fetch(request: Request, %s: Env): Promise<Response> {\n\
     %s\n\
    \  }\n\
     };\n"
    env_type_block env_param (String.concat "\n" body_lines)

(** Convert worker groups to IR config. *)
let to_ir (groups : worker_group list)
    (analysis : Scope.analysis_result) : Ir.config =
  List.map
    (fun group ->
       let kv_bindings =
         List.map
           (fun state_var ->
              Ir.KVBinding
                { name = String.uppercase_ascii state_var;
                  namespace_id =
                    Printf.sprintf "cloudlang-%s" state_var })
           group.owned_state
       in
       let svc_bindings =
         List.map
           (fun dep ->
              Ir.ServiceBinding
                { name = String.uppercase_ascii dep; service = dep })
           group.service_deps
       in
       let bindings = kv_bindings @ svc_bindings in
       let script = generate_worker_script group in
       let routes =
         (* If any function in this group is exported, add a route. *)
         let exported =
           List.filter
             (fun fn -> List.mem fn analysis.exports)
             group.functions
         in
         match exported with
         | [] -> []
         | _ -> [ Printf.sprintf "/%s" group.name ]
       in
       Ir.Worker { name = group.name; script; bindings; routes })
    groups
