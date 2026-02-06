# TypeScript JSON AST - Quick Reference

## TL;DR

✅ **Use `@typescript-eslint/typescript-estree`** for CloudLang compiler

**Why?**
- Clean JSON output (no circular references)
- ESTree standard format (well-documented)
- Best for OCaml deserialization (consistent structure)
- Battle-tested (used by ESLint, Prettier)

---

## The Three Approaches

```
┌─────────────────────────────────────────────────────────────────┐
│  Approach               │ JSON Output │ OCaml-friendly │ Status  │
├─────────────────────────┼─────────────┼────────────────┼─────────┤
│ Native TS Compiler API  │ ❌ Circular │ ❌ Irregular   │ ❌ Skip │
│ typescript-estree       │ ✅ Clean    │ ✅ Excellent   │ ✅ USE  │
│ Babel + TS plugin       │ ✅ Clean    │ ✅ Good        │ ⚠️ OK   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Example JSON Outputs

### Input: `const fn = (x: number) => x + 1;`

**typescript-estree output structure:**

```json
{
  "type": "Program",
  "body": [
    {
      "type": "VariableDeclaration",
      "declarations": [{
        "type": "VariableDeclarator",
        "id": { "type": "Identifier", "name": "fn" },
        "init": {
          "type": "ArrowFunctionExpression",
          "params": [{
            "type": "Identifier",
            "name": "x",
            "typeAnnotation": {
              "type": "TSTypeAnnotation",
              "typeAnnotation": { "type": "TSNumberKeyword" }
            }
          }],
          "body": {
            "type": "BinaryExpression",
            "operator": "+",
            "left": { "type": "Identifier", "name": "x" },
            "right": { "type": "Literal", "value": 1 }
          },
          "expression": true
        }
      }],
      "kind": "const"
    }
  ]
}
```

### Key Node Types (ESTree)

| Node Type | Description | Example |
|-----------|-------------|---------|
| `Program` | Root | Top-level container |
| `VariableDeclaration` | `const`/`let`/`var` | `const x = 42;` |
| `ArrowFunctionExpression` | Arrow function | `() => x` |
| `FunctionExpression` | Function literal | `function() {}` |
| `CallExpression` | Function call | `foo()` |
| `MemberExpression` | Property access | `obj.prop` |
| `Identifier` | Variable name | `x` |
| `Literal` | Primitive value | `42`, `"hello"` |
| `TSTypeAnnotation` | Type annotation | `: number` |

---

## CloudLang Integration Pattern

```
┌─────────────────┐
│  TypeScript     │
│  Input File     │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────┐
│  Node.js Bridge (subprocess)    │
│                                 │
│  require('typescript-estree')   │
│  .parse(code, { ... })          │
│  |> JSON.stringify              │
└────────┬────────────────────────┘
         │ stdout: JSON string
         ▼
┌─────────────────────────────────┐
│  OCaml: Jsont.decode            │
│                                 │
│  estree_program_dec json        │
└────────┬────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│  CloudLang AST                  │
│  (custom intermediate repr.)    │
└─────────────────────────────────┘
```

---

## Command to Generate AST

```bash
# Install dependency
npm install @typescript-eslint/typescript-estree

# Generate JSON AST
node -e "
const { parse } = require('@typescript-eslint/typescript-estree');
const fs = require('fs');
const code = fs.readFileSync(process.argv[1], 'utf-8');
const ast = parse(code, { loc: false, range: false });
console.log(JSON.stringify(ast, null, 2));
" input.ts > output.json
```

---

## OCaml Integration Example

```ocaml
(* Define ESTree types *)
type identifier = { name : string }

type arrow_function = {
  params : pattern list;
  body : statement_or_expr;
  expression : bool;
}

type estree_node =
  | Identifier of identifier
  | ArrowFunctionExpression of arrow_function
  (* ... *)

(* Parse JSON using jsont *)
let estree_dec =
  Jsont.Obj.case_map "type" [
    "Identifier", identifier_dec;
    "ArrowFunctionExpression", arrow_function_dec;
    (* ... *)
  ]

(* Main parser function *)
let parse_typescript_file filepath =
  let json_output = 
    let cmd = Printf.sprintf "node tools/ts-to-ast.js %s" filepath in
    Unix.open_process_in cmd
    |> In_channel.input_all
  in
  Jsont.decode estree_program_dec json_output
  |> convert_to_cloudlang_ast
```

---

## Important Notes

### Closures are NOT Explicit in AST

```typescript
const cache = new Map();
const get = (key: string) => cache.get(key);
//                            ^^^^^ Just an Identifier reference
```

**You must implement scope analysis in OCaml** to detect:
- Free variables in arrow functions
- Which variables are captured from outer scopes
- Closure conversion strategy

### TypeScript Type Annotations

TypeScript-specific nodes use `TS` prefix:

- `TSTypeAnnotation`: Wraps type syntax (`: number`)
- `TSNumberKeyword`: `number` type
- `TSStringKeyword`: `string` type
- `TSUnionType`: `A | B`
- `TSFunctionType`: `(x: T) => U`

These should be mapped to CloudLang's type system.

---

## Next Steps for CloudLang

1. **Create `tools/ts-to-ast.js`**
   - Wrapper script around typescript-estree
   - Takes TypeScript file path as argument
   - Outputs JSON to stdout

2. **Define ESTree types in OCaml**
   - Use `jsont` for type-safe deserialization
   - Map to CloudLang AST types

3. **Implement scope analysis**
   - Track variable declarations
   - Identify free variables in functions
   - Build closure capture sets

4. **Convert ESTree → CloudLang IR**
   - Handle Cloudflare-specific patterns
   - Map Workers, Durable Objects, R2, D1 APIs

---

**See full research:** `.opencode/context/typescript-ast-json-research.md`
