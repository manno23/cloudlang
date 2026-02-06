(** CloudLang: TypeScript -> Cloudflare Worker decomposition compiler.

    Pipeline:
    1. [analyze]: TypeScript ESTree AST -> scope/closure analysis
    2. [compile]: analysis result -> IR config (Workers + bindings)
    3. [generate]: IR config -> output string (wrangler configs + TS scripts) *)

module Ast = Ast
module Ir = Ir
module Scope = Scope
module Decompose = Decompose

type error = string

val analyze : Ast.node -> (Scope.analysis_result, error) result
val compile : Scope.analysis_result -> (Ir.config, error) result
val generate : Ir.config -> string
