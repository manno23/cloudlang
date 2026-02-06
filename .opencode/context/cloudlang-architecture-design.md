# CloudLang Compiler Architecture Design

**Date:** 2026-02-06  
**Status:** Research / Design Phase

## High-Level Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                    CloudLang Compiler Pipeline                     │
└────────────────────────────────────────────────────────────────────┘

    ┌──────────────┐
    │ TypeScript   │
    │ Source File  │
    │              │
    │ worker.ts    │
    └──────┬───────┘
           │
           │ 1. Parse to ESTree JSON
           ▼
    ┌──────────────────────────────┐
    │  Node.js Bridge              │
    │  (typescript-estree)         │
    │                              │
    │  • Subprocess invocation     │
    │  • JSON serialization        │
    └──────┬───────────────────────┘
           │ JSON (ESTree format)
           │
           │ 2. Deserialize to OCaml types
           ▼
    ┌──────────────────────────────┐
    │  ESTree AST (OCaml)          │
    │                              │
    │  • Type-safe representation  │
    │  • jsont decoder             │
    └──────┬───────────────────────┘
           │
           │ 3. Semantic Analysis
           ▼
    ┌──────────────────────────────┐
    │  CloudLang AST               │
    │                              │
    │  • Scope analysis            │
    │  • Closure detection         │
    │  • Type inference            │
    └──────┬───────────────────────┘
           │
           │ 4. Lower to IR
           ▼
    ┌──────────────────────────────┐
    │  CloudLang IR                │
    │                              │
    │  • Simplified representation │
    │  • Platform-agnostic         │
    └──────┬───────────────────────┘
           │
           │ 5. Code Generation
           ▼
    ┌──────────────────────────────┐
    │  Cloudflare Config           │
    │                              │
    │  • wrangler.toml             │
    │  • Worker bindings           │
    │  • DO declarations           │
    │  • R2/D1 schemas             │
    └──────────────────────────────┘
```

---

## Component Breakdown

### Phase 1: TypeScript → ESTree JSON

**Input:** TypeScript source file  
**Output:** JSON string (ESTree-compatible AST)  
**Tool:** `@typescript-eslint/typescript-estree`

```
┌─────────────────────────────────────────────────────────────┐
│  tools/ts-to-ast.js                                         │
│  ────────────────────                                       │
│                                                             │
│  const { parse } = require('@typescript-eslint/...');      │
│  const fs = require('fs');                                 │
│                                                             │
│  const code = fs.readFileSync(process.argv[1], 'utf-8');   │
│  const ast = parse(code, { loc: false, range: false });    │
│  console.log(JSON.stringify(ast));                         │
└─────────────────────────────────────────────────────────────┘
          │
          │ Invoked from OCaml:
          │   Unix.open_process_in "node tools/ts-to-ast.js input.ts"
          ▼
     JSON string (stdout)
```

**Advantages:**
- ✅ No TypeScript compiler integration in OCaml
- ✅ Leverage mature TypeScript parser
- ✅ Clean separation of concerns

**Disadvantages:**
- ⚠️ Requires Node.js runtime
- ⚠️ Subprocess overhead (negligible for single-file compiles)

---

### Phase 2: JSON → OCaml ESTree Types

**Input:** JSON string  
**Output:** Type-safe OCaml `estree_ast` value  
**Tool:** `jsont` library

```ocaml
(* lib/estree.ml *)

type identifier = { name : string }

type literal = {
  value : Yojson.Basic.t;  (* Can be number, string, bool, null *)
  raw : string;
}

type arrow_function_expression = {
  params : pattern list;
  body : statement_or_expression;
  expression : bool;  (* true = implicit return *)
  async : bool;
  generator : bool;
}

type variable_declarator = {
  id : pattern;
  init : expression option;
}

type variable_declaration = {
  declarations : variable_declarator list;
  kind : [ `Const | `Let | `Var ];
}

(* ... more types *)

type statement =
  | VariableDeclaration of variable_declaration
  | ExportDefaultDeclaration of export_default_declaration
  | ReturnStatement of return_statement
  (* ... *)

type expression =
  | Identifier of identifier
  | Literal of literal
  | ArrowFunctionExpression of arrow_function_expression
  | CallExpression of call_expression
  | MemberExpression of member_expression
  (* ... *)

type program = {
  body : statement list;
  source_type : [ `Script | `Module ];
}
```

**Jsont Decoder Example:**

```ocaml
(* lib/estree_decoder.ml *)

open Jsont

let identifier_dec =
  Jsont.Obj.map ~kind:"Identifier"
    (fun name -> { name })
    (Jsont.Obj.mem "name" Jsont.string)

let literal_dec =
  Jsont.Obj.map ~kind:"Literal"
    (fun value raw -> { value; raw })
    (Jsont.Obj.mem "value" Jsont.any)
    (Jsont.Obj.mem "raw" Jsont.string)

(* Recursive decoder for expressions *)
let rec expression_dec =
  Jsont.Obj.case_map "type" [
    "Identifier", Jsont.map (fun x -> Identifier x) identifier_dec;
    "Literal", Jsont.map (fun x -> Literal x) literal_dec;
    "ArrowFunctionExpression", 
      Jsont.map (fun x -> ArrowFunctionExpression x) arrow_function_dec;
    (* ... *)
  ]

and arrow_function_dec =
  Jsont.Obj.map ~kind:"ArrowFunctionExpression"
    (fun params body expression async generator -> 
      { params; body; expression; async; generator })
    (Jsont.Obj.mem "params" (Jsont.array pattern_dec))
    (Jsont.Obj.mem "body" statement_or_expression_dec)
    (Jsont.Obj.mem "expression" Jsont.bool)
    (Jsont.Obj.mem "async" Jsont.bool)
    (Jsont.Obj.mem "generator" Jsont.bool)

let program_dec =
  Jsont.Obj.map ~kind:"Program"
    (fun body source_type -> { body; source_type })
    (Jsont.Obj.mem "body" (Jsont.array statement_dec))
    (Jsont.Obj.opt_mem "sourceType" 
      (Jsont.enum ["script", `Script; "module", `Module]))
```

---

### Phase 3: ESTree → CloudLang AST (Semantic Analysis)

**Input:** ESTree AST (OCaml types)  
**Output:** CloudLang AST with semantic information  
**Processing:**
1. **Scope Analysis:** Track variable declarations and references
2. **Closure Detection:** Identify captured variables
3. **Type Inference:** Infer CloudLang types from TypeScript annotations
4. **Cloudflare API Recognition:** Detect Workers, DO, R2, D1 patterns

```ocaml
(* lib/semantic_analysis.ml *)

type cloudlang_type =
  | TNumber
  | TString
  | TBool
  | TFunction of cloudlang_type list * cloudlang_type
  | TObject of (string * cloudlang_type) list
  | TUnknown

type binding = {
  name : string;
  ty : cloudlang_type;
  mutable is_captured : bool;  (* Set to true if used in closure *)
}

type scope = {
  bindings : (string, binding) Hashtbl.t;
  parent : scope option;
}

type cloudlang_expr =
  | CLVar of { name : string; binding : binding }
  | CLLiteral of literal
  | CLFunction of {
      params : (string * cloudlang_type) list;
      body : cloudlang_expr;
      captures : binding list;  (* Closure captures *)
    }
  | CLCall of { callee : cloudlang_expr; args : cloudlang_expr list }
  (* ... *)

let rec analyze_expression (scope : scope) (expr : Estree.expression) 
  : cloudlang_expr =
  match expr with
  | Identifier { name } ->
      let binding = lookup_binding scope name in
      CLVar { name; binding }
  
  | ArrowFunctionExpression { params; body; expression; _ } ->
      let inner_scope = create_child_scope scope in
      let params' = List.map (analyze_param inner_scope) params in
      let body' = analyze_body inner_scope body expression in
      let captures = find_free_variables inner_scope body' in
      (* Mark captured bindings *)
      List.iter (fun b -> b.is_captured <- true) captures;
      CLFunction { params = params'; body = body'; captures }
  
  | CallExpression { callee; arguments; _ } ->
      let callee' = analyze_expression scope callee in
      let args' = List.map (analyze_expression scope) arguments in
      CLCall { callee = callee'; args = args' }
  
  (* ... *)

and find_free_variables (scope : scope) (expr : cloudlang_expr) 
  : binding list =
  (* Collect all CLVar bindings not defined in current scope *)
  (* ... *)
```

**Cloudflare Pattern Recognition:**

```ocaml
(* lib/cloudflare_patterns.ml *)

type cloudflare_entity =
  | Worker of { fetch_handler : cloudlang_expr }
  | DurableObject of {
      class_name : string;
      methods : (string * cloudlang_expr) list;
    }
  | R2Binding of { binding_name : string }
  | D1Binding of { binding_name : string }

let recognize_pattern (ast : cloudlang_ast) : cloudflare_entity option =
  match ast with
  (* export default { fetch(request, env) { ... } } *)
  | ExportDefault (ObjectLiteral props) when has_fetch_method props ->
      Some (Worker { fetch_handler = extract_fetch_handler props })
  
  (* export default { fetch(...) { ... }, alarm(...) { ... } } *)
  | ExportDefault (ObjectLiteral props) when has_do_methods props ->
      Some (DurableObject { 
        class_name = "TODO"; 
        methods = extract_do_methods props 
      })
  
  | _ -> None
```

---

### Phase 4: CloudLang AST → CloudLang IR

**Purpose:** Simplify AST for code generation

```ocaml
(* lib/ir.ml *)

type ir_value =
  | ILiteral of literal
  | IVar of string
  | IClosure of {
      params : string list;
      body : ir_instr list;
      captures : string list;
    }

and ir_instr =
  | ILet of { name : string; value : ir_value }
  | ICall of { target : ir_value; args : ir_value list }
  | IReturn of ir_value
  (* ... *)

type ir_program = ir_instr list

let lower_to_ir (ast : cloudlang_ast) : ir_program =
  (* Convert CloudLang AST to simpler IR *)
  (* ... *)
```

---

### Phase 5: IR → Cloudflare Configuration

**Output Formats:**

1. **wrangler.toml**
2. **Worker TypeScript/JavaScript** (if needed)
3. **Durable Object class declarations**
4. **R2/D1 schema definitions**

```ocaml
(* lib/codegen/worker_gen.ml *)

let generate_worker (ir : ir_program) (pattern : cloudflare_entity) 
  : string =
  match pattern with
  | Worker { fetch_handler } ->
      Printf.sprintf
        "export default {\n\
         \  async fetch(request, env, ctx) {\n\
         \    %s\n\
         \  }\n\
         }"
        (generate_ir_as_js fetch_handler)

(* lib/codegen/wrangler_gen.ml *)

let generate_wrangler_toml (config : cloudflare_config) : string =
  Printf.sprintf
    "name = \"%s\"\n\
     main = \"src/index.ts\"\n\
     compatibility_date = \"2026-02-06\"\n\
     \n\
     [durable_objects]\n\
     bindings = [\n\
     %s\
     ]\n"
    config.worker_name
    (generate_do_bindings config.durable_objects)
```

---

## Closure Handling Strategy

### Detection

```ocaml
(* Scope analysis pass *)
let rec find_free_variables scope expr =
  match expr with
  | CLVar { name; binding } ->
      if not (defined_in_current_scope scope name) then
        [binding]
      else
        []
  | CLFunction { body; _ } ->
      (* Recursively find free vars in nested function *)
      find_free_variables scope body
  | CLCall { callee; args } ->
      List.concat [
        find_free_variables scope callee;
        List.concat_map (find_free_variables scope) args;
      ]
  (* ... *)
```

### Representation

```
TypeScript Input:
─────────────────
const cache = new Map();
const get = (key: string) => cache.get(key);

CloudLang AST:
──────────────
ExportDefault (
  ObjectLiteral [
    ("get", CLFunction {
      params = [("key", TString)];
      body = CLCall { ... };
      captures = [cache_binding];  ← Detected!
    })
  ]
)

CloudFlare Output Strategy:
───────────────────────────
1. Lift closure to object property
2. Use Durable Object state for persistence
3. Or: Use Worker module-level scope
```

---

## Type System Mapping

```
┌─────────────────────────────────────────────────────────────┐
│  TypeScript Type    │  CloudLang Type  │  Cloudflare API   │
├─────────────────────┼──────────────────┼───────────────────┤
│  number             │  TNumber         │  number           │
│  string             │  TString         │  string           │
│  boolean            │  TBool           │  boolean          │
│  Request            │  TRequest        │  Request          │
│  Response           │  TResponse       │  Response         │
│  Map<K, V>          │  TMap(K, V)      │  Map<K, V>        │
│  DurableObjectState │  TDOState        │  DurableObjectState│
│  R2Bucket           │  TR2Bucket       │  R2Bucket         │
│  D1Database         │  TD1Database     │  D1Database       │
└─────────────────────────────────────────────────────────────┘
```

---

## Error Handling

Each phase should produce actionable error messages:

```ocaml
type compile_error =
  | ParseError of { line : int; col : int; msg : string }
  | TypeError of { expr : cloudlang_expr; expected : ty; actual : ty }
  | UndefinedVariable of { name : string; location : location }
  | InvalidCloudflarePattern of { reason : string }

exception CompilationFailed of compile_error list

let compile_file (filepath : string) : (ir_program, compile_error list) result =
  try
    filepath
    |> parse_typescript_file
    |> analyze_semantics
    |> lower_to_ir
    |> Ok
  with
  | CompilationFailed errors -> Error errors
```

---

## File Structure

```
cloudlang/
├── lib/
│   ├── estree.ml           # ESTree type definitions
│   ├── estree_decoder.ml   # Jsont decoders for ESTree
│   ├── ast.ml              # CloudLang AST types
│   ├── semantic_analysis.ml # Scope, closure, type inference
│   ├── ir.ml               # Intermediate representation
│   ├── cloudflare_patterns.ml # Pattern matching for CF APIs
│   ├── codegen/
│   │   ├── worker_gen.ml   # Generate Worker code
│   │   ├── durable_object_gen.ml
│   │   ├── wrangler_gen.ml # Generate wrangler.toml
│   │   └── codegen.ml      # Main codegen orchestration
│   └── cloudlang.ml        # Library public interface
├── bin/
│   └── main.ml             # CLI entry point
├── tools/
│   └── ts-to-ast.js        # Node.js bridge script
└── test/
    ├── unit/
    │   ├── test_estree_decoder.ml
    │   ├── test_semantic_analysis.ml
    │   └── test_codegen.ml
    └── integration/
        └── test_end_to_end.ml
```

---

## Next Implementation Steps

### Milestone 1: Basic Pipeline (MVP)
- [x] Research TypeScript AST approaches
- [ ] Implement `tools/ts-to-ast.js`
- [ ] Define core ESTree types in OCaml
- [ ] Implement basic jsont decoders
- [ ] Parse simple TypeScript: `const x = 42;`

### Milestone 2: Function Support
- [ ] Handle function declarations
- [ ] Handle arrow functions
- [ ] Basic scope analysis (no closures yet)
- [ ] Generate simple Worker

### Milestone 3: Closure Support
- [ ] Implement closure detection
- [ ] Track captured variables
- [ ] Generate closures in IR
- [ ] Test with complex examples

### Milestone 4: Cloudflare APIs
- [ ] Recognize Worker fetch handler
- [ ] Recognize Durable Object patterns
- [ ] R2 bucket access
- [ ] D1 database queries
- [ ] Generate wrangler.toml

### Milestone 5: Type System
- [ ] TypeScript type annotation parsing
- [ ] CloudLang type inference
- [ ] Type checking
- [ ] Type error messages

---

**End of Architecture Design Document**
