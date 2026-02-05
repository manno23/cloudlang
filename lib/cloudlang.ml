module Ast = Ast
module Ir = Ir

type error = string

let parse (_s : string) : (Ast.program, error) result =
  Ok []  (* TODO: implement actual parser *)

let typecheck (p : Ast.program) : (Ast.program, error) result =
  Ok p   (* TODO: implement type checker *)

let compile (_p : Ast.program) : (Ir.config, error) result =
  Ok []  (* TODO: implement compiler *)

let generate (_c : Ir.config) : string =
  "{}"   (* TODO: implement JSON/TS config generator *)
