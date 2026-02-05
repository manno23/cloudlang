module Ast : sig
  type loc = { line : int; column : int }

  type ty =
    | TInt
    | TBool
    | TString
    | TArrow of ty * ty
    | TUnit

  type expr =
    | Var of string * loc
    | Int of int * loc
    | Bool of bool * loc
    | String of string * loc
    | Lambda of string * ty * expr * loc
    | App of expr * expr * loc
    | Let of string * expr * expr * loc
    | PrimOp of string * expr list * loc

  type stmt =
    | Define of string * expr * loc
    | Export of string * loc

  type program = stmt list
end

module Ir : sig
  type worker = {
    name : string;
    script : string;
    routes : string list;
  }

  type durable_object = {
    class_name : string;
    script : string;
  }

  type r2_bucket = {
    name : string;
    location : string;
  }

  type d1_database = {
    name : string;
    schema : string;
  }

  type resource =
    | Worker of worker
    | DurableObject of durable_object
    | R2Bucket of r2_bucket
    | D1Database of d1_database

  type config = resource list
end

type error = string

val parse : string -> (Ast.program, error) result
val typecheck : Ast.program -> (Ast.program, error) result
val compile : Ast.program -> (Ir.config, error) result
val generate : Ir.config -> string
