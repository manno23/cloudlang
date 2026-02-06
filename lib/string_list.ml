(** Deduplicate a string list while preserving first-occurrence order. *)
let dedup_preserve_order (xs : string list) : string list =
  let seen = Hashtbl.create (List.length xs) in
  List.rev
    (List.fold_left
       (fun acc x ->
         if Hashtbl.mem seen x then acc
         else (
           Hashtbl.add seen x ();
           x :: acc))
       [] xs)
