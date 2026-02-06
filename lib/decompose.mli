(** Closure decomposition: scope analysis results -> IR config.

    Groups closures into Workers based on shared mutable state,
    generates KV bindings for mutable state and service bindings
    for cross-group function calls. *)

(** A logical group of functions that will become a single Worker. *)
type worker_group = {
  name : string;
  functions : string list;
  owned_state : string list;
  service_deps : string list;
}

val decompose : Scope.analysis_result -> worker_group list

val to_ir : worker_group list -> Scope.analysis_result -> Ir.config
