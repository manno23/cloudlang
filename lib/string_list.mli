(** String list helpers. *)

val dedup_preserve_order : string list -> string list
(** [dedup_preserve_order xs] removes duplicate values from [xs], preserving
    first-occurrence order. *)
