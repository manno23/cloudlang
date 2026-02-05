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
