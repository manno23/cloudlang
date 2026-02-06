(** Scope analysis for TypeScript ESTree AST.

    Walks the AST to build a scope tree, identify variable declarations,
    and compute free variables for each arrow function (closure). *)

(** Information about a declared variable. *)
type var_info = {
  name : string;
  is_mutable_state : bool;
    (** [true] when the initialiser is [new Map()], [new Set()], etc. *)
  is_function : bool;
    (** [true] when the initialiser is an [ArrowFunctionExpression]. *)
}

(** Per-closure analysis result. *)
type closure_info = {
  name : string;
    (** The [const] name this arrow function is assigned to. *)
  free_vars : string list;
    (** Variables referenced from outer scopes. *)
  called_functions : string list;
    (** Names of other module-level functions called in the body. *)
  captures_mutable : string list;
    (** Subset of [free_vars] that are mutable state variables. *)
}

(** Complete analysis result for a program. *)
type analysis_result = {
  closures : closure_info list;
  module_vars : var_info list;
    (** All module-scope variable declarations. *)
  exports : string list;
    (** Names appearing in [export { ... }] declarations. *)
}

val analyze : Ast.node -> analysis_result
