(** Scope analysis for TypeScript ESTree AST.

    Two-pass analysis:
    1. Declaration pass: collect all module-scope const/let bindings,
       noting which are mutable state (new Map/Set) and which are functions.
    2. Reference pass: for each arrow function body, collect Identifier
       references that are not locally declared -> these are free variables. *)

type var_info = {
  name : string;
  is_mutable_state : bool;
  is_function : bool;
}

type closure_info = {
  name : string;
  free_vars : string list;
  called_functions : string list;
  captures_mutable : string list;
}

type analysis_result = {
  closures : closure_info list;
  module_vars : var_info list;
  exports : string list;
}

(** Deduplicate a string list, preserving first-occurrence order. *)
let dedup xs =
  List.fold_left
    (fun acc x -> if List.mem x acc then acc else acc @ [ x ])
    [] xs

(** Check whether an init expression is [new Map(...)], [new Set(...)], etc. *)
let is_mutable_init = function
  | Ast.NewExpression { callee = Ast.Identifier { name }; _ }
    when name = "Map" || name = "Set" || name = "Array" ->
    true
  | _ -> false

(** Check whether an init expression is an arrow function. *)
let is_arrow_init = function
  | Ast.ArrowFunctionExpression _ -> true
  | _ -> false

(** Extract parameter names from an arrow function's param list. *)
let param_names params =
  List.filter_map
    (function Ast.Identifier { name } -> Some name | _ -> None)
    params

(** Collect all identifiers referenced in an expression/statement,
    excluding property names on the right side of member expressions. *)
let rec collect_refs (node : Ast.node) : string list =
  match node with
  | Ast.Identifier { name } -> [ name ]
  | Ast.Literal _ -> []
  | Ast.MemberExpression { object_; _ } ->
    (* Only the object side can be a free variable reference.
       e.g. in [store.set(k, v)], [store] is a ref but [set] is not. *)
    collect_refs object_
  | Ast.CallExpression { callee; arguments } ->
    collect_refs callee @ List.concat_map collect_refs arguments
  | Ast.BinaryExpression { left; right; _ }
  | Ast.LogicalExpression { left; right; _ } ->
    collect_refs left @ collect_refs right
  | Ast.BlockStatement { body } -> List.concat_map collect_refs body
  | Ast.ExpressionStatement { expression } -> collect_refs expression
  | Ast.ReturnStatement { argument } ->
    (match argument with Some a -> collect_refs a | None -> [])
  | Ast.IfStatement { test; consequent; alternate } ->
    collect_refs test @ collect_refs consequent
    @ (match alternate with Some a -> collect_refs a | None -> [])
  | Ast.VariableDeclaration { declarations; _ } ->
    List.concat_map collect_refs declarations
  | Ast.VariableDeclarator { init; _ } ->
    (match init with Some i -> collect_refs i | None -> [])
  | Ast.NewExpression { callee; arguments } ->
    collect_refs callee @ List.concat_map collect_refs arguments
  | Ast.ArrowFunctionExpression _ ->
    (* Don't descend into nested arrow functions for the outer scope's
       reference collection. Each arrow function is analysed separately. *)
    []
  | Ast.Program { body } -> List.concat_map collect_refs body
  | Ast.ExportNamedDeclaration _ | Ast.ExportSpecifier _ -> []

(** Collect names of functions being called as simple identifiers.
    e.g. [get(key)] yields ["get"], but [cache.get(key)] yields []. *)
let rec collect_called_functions (node : Ast.node) : string list =
  match node with
  | Ast.CallExpression { callee = Ast.Identifier { name }; arguments } ->
    [ name ] @ List.concat_map collect_called_functions arguments
  | Ast.CallExpression { callee; arguments } ->
    collect_called_functions callee
    @ List.concat_map collect_called_functions arguments
  | Ast.BlockStatement { body } ->
    List.concat_map collect_called_functions body
  | Ast.ExpressionStatement { expression } ->
    collect_called_functions expression
  | Ast.ReturnStatement { argument } ->
    (match argument with
     Some a -> collect_called_functions a | None -> [])
  | Ast.IfStatement { test; consequent; alternate } ->
    collect_called_functions test
    @ collect_called_functions consequent
    @ (match alternate with
       Some a -> collect_called_functions a | None -> [])
  | Ast.BinaryExpression { left; right; _ }
  | Ast.LogicalExpression { left; right; _ } ->
    collect_called_functions left @ collect_called_functions right
  | Ast.VariableDeclaration { declarations; _ } ->
    List.concat_map collect_called_functions declarations
  | Ast.VariableDeclarator { init; _ } ->
    (match init with Some i -> collect_called_functions i | None -> [])
  | Ast.MemberExpression { object_; _ } ->
    collect_called_functions object_
  | _ -> []

(** Collect local variable names declared inside a block (one level deep,
    not descending into nested arrow functions). *)
let rec collect_locals (node : Ast.node) : string list =
  match node with
  | Ast.BlockStatement { body } -> List.concat_map collect_locals body
  | Ast.VariableDeclaration { declarations; _ } ->
    List.filter_map
      (function
        | Ast.VariableDeclarator { id = Ast.Identifier { name }; _ } ->
          Some name
        | _ -> None)
      declarations
  | Ast.IfStatement { consequent; alternate; _ } ->
    collect_locals consequent
    @ (match alternate with Some a -> collect_locals a | None -> [])
  | _ -> []

(** Analyse a single arrow function: compute its free variables,
    the functions it calls, and which captured variables are mutable state. *)
let analyse_closure (name : string) (params : Ast.node list)
    (body : Ast.node) (module_vars : var_info list) : closure_info =
  let param_set = param_names params in
  let locals = collect_locals body in
  let bound = param_set @ locals in
  let all_refs = dedup (collect_refs body) in
  let free_vars =
    List.filter
      (fun r ->
         (not (List.mem r bound))
         && List.exists (fun (v : var_info) -> v.name = r) module_vars)
      all_refs
  in
  let all_called = dedup (collect_called_functions body) in
  let called_functions =
    List.filter
      (fun f ->
         (not (List.mem f bound))
         && List.exists
              (fun (v : var_info) -> v.name = f && v.is_function)
              module_vars)
      all_called
  in
  let captures_mutable =
    List.filter
      (fun fv ->
         List.exists
           (fun (v : var_info) -> v.name = fv && v.is_mutable_state)
           module_vars)
      free_vars
  in
  { name; free_vars; called_functions; captures_mutable }

(** Top-level analysis entry point. Expects a [Program] node. *)
let analyze (program : Ast.node) : analysis_result =
  let body =
    match program with
    | Ast.Program { body } -> body
    | _ -> failwith "analyze: expected Program node"
  in
  (* Pass 1: collect module-scope declarations *)
  let module_vars =
    List.concat_map
      (function
        | Ast.VariableDeclaration { declarations; _ } ->
          List.filter_map
            (function
              | Ast.VariableDeclarator
                  { id = Ast.Identifier { name }; init } ->
                let is_mutable_state =
                  match init with Some i -> is_mutable_init i | None -> false
                in
                let is_function =
                  match init with Some i -> is_arrow_init i | None -> false
                in
                Some { name; is_mutable_state; is_function }
              | _ -> None)
            declarations
        | _ -> [])
      body
  in
  (* Pass 2: analyse each arrow function *)
  let closures =
    List.filter_map
      (function
        | Ast.VariableDeclaration
            {
              declarations =
                [
                  Ast.VariableDeclarator
                    {
                      id = Ast.Identifier { name };
                      init =
                        Some
                          (Ast.ArrowFunctionExpression
                            { params; body; _ });
                    };
                ];
              _;
            } ->
          Some (analyse_closure name params body module_vars)
        | _ -> None)
      body
  in
  (* Pass 3: collect exports *)
  let exports =
    List.concat_map
      (function
        | Ast.ExportNamedDeclaration { specifiers } ->
          List.filter_map
            (function
              | Ast.ExportSpecifier { local = Ast.Identifier { name } } ->
                Some name
              | _ -> None)
            specifiers
        | _ -> [])
      body
  in
  { closures; module_vars; exports }
