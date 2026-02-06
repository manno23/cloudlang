# TypeScript to JSON AST Research Findings

**Date:** 2026-02-06  
**Purpose:** Evaluate approaches for parsing TypeScript code into JSON AST for CloudLang compiler

## Executive Summary

There are **three main approaches** to generate JSON AST from TypeScript:

1. **Native TypeScript Compiler API** (`ts.createSourceFile` + manual serialization)
2. **@typescript-eslint/typescript-estree** (ESTree-compatible)
3. **@babel/parser** with TypeScript plugin (ESTree-compatible)

**Recommendation:** Use `@typescript-eslint/typescript-estree` for OCaml integration.

---

## 1. Approaches Comparison

### 1.1 Native TypeScript Compiler API

```typescript
import * as ts from 'typescript';

const code = `const x = 42;`;
const sourceFile = ts.createSourceFile(
  'file.ts',
  code,
  ts.ScriptTarget.Latest,
  true
);

// Manual serialization required (circular references!)
const getCircularReplacer = () => {
  const seen = new WeakSet();
  return (key, value) => {
    if (typeof value === "object" && value !== null) {
      if (seen.has(value)) return;
      seen.add(value);
    }
    return value;
  };
};

const json = JSON.stringify(sourceFile, getCircularReplacer());
```

**Pros:**
- Direct access to TypeScript's native AST
- Full type information available
- Most accurate TypeScript semantics

**Cons:**
- ❌ **Circular references** require custom serialization
- ❌ Non-standard AST format (TypeScript-specific)
- ❌ Irregular structure, harder to deserialize in OCaml
- ❌ No official JSON output from `tsc` (as of 2026, still not supported)

### 1.2 @typescript-eslint/typescript-estree ✅ RECOMMENDED

```typescript
import { parse } from '@typescript-eslint/typescript-estree';

const code = `const x = 42;`;
const ast = parse(code, {
  loc: true,
  range: true,
  tokens: false,
  comment: false
});

const json = JSON.stringify(ast, null, 2);
```

**Pros:**
- ✅ **ESTree-compatible** standard format
- ✅ **No circular references** - clean JSON serialization
- ✅ Used by ESLint and Prettier (battle-tested)
- ✅ Regular, predictable structure
- ✅ Good for OCaml deserialization (consistent sum types)

**Cons:**
- Slightly different from native TypeScript AST
- Limited type information (focuses on syntax)

### 1.3 @babel/parser with TypeScript Plugin

```typescript
import { parse } from '@babel/parser';

const code = `const x = 42;`;
const ast = parse(code, {
  sourceType: 'module',
  plugins: ['typescript']
});

const json = JSON.stringify(ast, null, 2);
```

**Pros:**
- ✅ ESTree-compatible
- ✅ No circular references
- ✅ Widely used in build tools

**Cons:**
- TypeScript support is incomplete (focuses on syntax, not full type semantics)
- Less accurate for complex TypeScript features

---

## 2. JSON AST Structure Examples

### 2.1 Example: `const x = 42;`

**typescript-estree output:**

```json
{
  "type": "Program",
  "body": [
    {
      "type": "VariableDeclaration",
      "declarations": [
        {
          "type": "VariableDeclarator",
          "id": {
            "type": "Identifier",
            "name": "x"
          },
          "init": {
            "type": "Literal",
            "value": 42,
            "raw": "42"
          }
        }
      ],
      "kind": "const"
    }
  ],
  "sourceType": "script"
}
```

**Babel output:** (nearly identical structure)

```json
{
  "type": "File",
  "program": {
    "type": "Program",
    "body": [
      {
        "type": "VariableDeclaration",
        "declarations": [
          {
            "type": "VariableDeclarator",
            "id": {
              "type": "Identifier",
              "name": "x"
            },
            "init": {
              "type": "NumericLiteral",
              "value": 42
            }
          }
        ],
        "kind": "const"
      }
    ]
  }
}
```

### 2.2 Example: `const fn = (x: number) => x + 1;`

**typescript-estree output:**

```json
{
  "type": "Program",
  "body": [
    {
      "type": "VariableDeclaration",
      "declarations": [
        {
          "type": "VariableDeclarator",
          "id": {
            "type": "Identifier",
            "name": "fn"
          },
          "init": {
            "type": "ArrowFunctionExpression",
            "async": false,
            "expression": true,
            "generator": false,
            "params": [
              {
                "type": "Identifier",
                "name": "x",
                "typeAnnotation": {
                  "type": "TSTypeAnnotation",
                  "typeAnnotation": {
                    "type": "TSNumberKeyword"
                  }
                }
              }
            ],
            "body": {
              "type": "BinaryExpression",
              "operator": "+",
              "left": {
                "type": "Identifier",
                "name": "x"
              },
              "right": {
                "type": "Literal",
                "value": 1,
                "raw": "1"
              }
            }
          }
        }
      ],
      "kind": "const"
    }
  ],
  "sourceType": "script"
}
```

**Key observations:**
- TypeScript type annotations are preserved as `TSTypeAnnotation` nodes
- Arrow functions have `ArrowFunctionExpression` type
- `expression: true` indicates implicit return

### 2.3 Example: Arrow Function with Closure

```typescript
const cache = new Map();
const get = (key: string) => cache.get(key);
```

**typescript-estree output (simplified):**

```json
{
  "type": "Program",
  "body": [
    {
      "type": "VariableDeclaration",
      "declarations": [
        {
          "type": "VariableDeclarator",
          "id": { "type": "Identifier", "name": "cache" },
          "init": {
            "type": "NewExpression",
            "callee": { "type": "Identifier", "name": "Map" },
            "arguments": []
          }
        }
      ],
      "kind": "const"
    },
    {
      "type": "VariableDeclaration",
      "declarations": [
        {
          "type": "VariableDeclarator",
          "id": { "type": "Identifier", "name": "get" },
          "init": {
            "type": "ArrowFunctionExpression",
            "params": [
              {
                "type": "Identifier",
                "name": "key",
                "typeAnnotation": {
                  "type": "TSTypeAnnotation",
                  "typeAnnotation": { "type": "TSStringKeyword" }
                }
              }
            ],
            "body": {
              "type": "CallExpression",
              "callee": {
                "type": "MemberExpression",
                "object": { "type": "Identifier", "name": "cache" },
                "property": { "type": "Identifier", "name": "get" }
              },
              "arguments": [
                { "type": "Identifier", "name": "key" }
              ]
            }
          }
        }
      ],
      "kind": "const"
    }
  ]
}
```

**Key observations:**
- Closure variable `cache` is just an `Identifier` reference (no explicit "capture" metadata)
- Semantic analysis required to detect closures
- Scope analysis needed to determine free variables

### 2.4 Example: `export default { fetch(request) { ... } }`

```typescript
export default { 
  fetch(request) { 
    return new Response('hello'); 
  } 
}
```

**typescript-estree output (simplified):**

```json
{
  "type": "Program",
  "body": [
    {
      "type": "ExportDefaultDeclaration",
      "declaration": {
        "type": "ObjectExpression",
        "properties": [
          {
            "type": "Property",
            "key": { "type": "Identifier", "name": "fetch" },
            "computed": false,
            "method": true,
            "shorthand": false,
            "value": {
              "type": "FunctionExpression",
              "id": null,
              "params": [
                { "type": "Identifier", "name": "request" }
              ],
              "body": {
                "type": "BlockStatement",
                "body": [
                  {
                    "type": "ReturnStatement",
                    "argument": {
                      "type": "NewExpression",
                      "callee": { "type": "Identifier", "name": "Response" },
                      "arguments": [
                        {
                          "type": "Literal",
                          "value": "hello",
                          "raw": "'hello'"
                        }
                      ]
                    }
                  }
                ]
              }
            }
          }
        ]
      }
    }
  ],
  "sourceType": "module"
}
```

**Key observations:**
- `ExportDefaultDeclaration` wraps the export
- Object method shorthand: `method: true`
- `FunctionExpression` for the method body

---

## 3. OCaml Integration Considerations

### 3.1 Why typescript-estree is Best for OCaml

1. **Consistent Sum Types**: ESTree node types map cleanly to OCaml variants:

```ocaml
type estree_node =
  | Program of program
  | VariableDeclaration of variable_declaration
  | ArrowFunctionExpression of arrow_function
  | Identifier of identifier
  | Literal of literal
  (* ... *)
```

2. **No Circular References**: Direct `Yojson.Basic.from_string` works without preprocessing

3. **Predictable Structure**: Every node has:
   - `type` field (discriminator for OCaml variants)
   - Consistent field names

4. **Well-Documented**: ESTree spec is standardized

### 3.2 Recommended OCaml Workflow

```
┌─────────────┐
│ TypeScript  │
│   Source    │
└──────┬──────┘
       │
       ▼
┌─────────────────────────┐
│ typescript-estree       │
│ (Node.js subprocess)    │
└──────┬──────────────────┘
       │ stdout: JSON
       ▼
┌─────────────────────────┐
│ OCaml: Yojson.Basic     │
│   parse JSON string     │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ OCaml: Convert to       │
│   CloudLang AST         │
└─────────────────────────┘
```

### 3.3 Alternative: Use jsont for Typed Deserialization

```ocaml
open Jsont

type identifier = { name : string }
type literal = { value : json; raw : string }

type estree_node =
  | Identifier of identifier
  | Literal of literal
  (* ... *)

let identifier_dec =
  Jsont.Obj.map ~kind:"Identifier"
    (fun name -> { name })
    (Jsont.Obj.mem "name" Jsont.string)

let literal_dec =
  Jsont.Obj.map ~kind:"Literal"
    (fun value raw -> { value; raw })
    (Jsont.Obj.mem "value" Jsont.any)
    (Jsont.Obj.mem "raw" Jsont.string)

(* Discriminated union based on "type" field *)
let estree_node_dec =
  Jsont.Obj.case_map "type" [
    "Identifier", identifier_dec;
    "Literal", literal_dec;
    (* ... *)
  ]
```

---

## 4. Command-Line Usage

### 4.1 typescript-estree

```bash
# Install
npm install @typescript-eslint/typescript-estree

# Node.js script
node -e "
const { parse } = require('@typescript-eslint/typescript-estree');
const fs = require('fs');

const code = fs.readFileSync(process.argv[1], 'utf-8');
const ast = parse(code, { loc: false, range: false });
console.log(JSON.stringify(ast));
" input.ts > output.json
```

### 4.2 babel/parser

```bash
# Install
npm install @babel/parser

# Node.js script
node -e "
const { parse } = require('@babel/parser');
const fs = require('fs');

const code = fs.readFileSync(process.argv[1], 'utf-8');
const ast = parse(code, { 
  sourceType: 'module',
  plugins: ['typescript']
});
console.log(JSON.stringify(ast));
" input.ts > output.json
```

---

## 5. AST Node Types Reference (ESTree)

### Common Node Types for CloudLang

| Node Type | Description | Key Fields |
|-----------|-------------|------------|
| `Program` | Root node | `body: Statement[]` |
| `VariableDeclaration` | `const`/`let`/`var` | `kind`, `declarations` |
| `VariableDeclarator` | Single variable | `id`, `init` |
| `FunctionDeclaration` | Named function | `id`, `params`, `body` |
| `ArrowFunctionExpression` | Arrow function | `params`, `body`, `expression` |
| `CallExpression` | Function call | `callee`, `arguments` |
| `MemberExpression` | Property access | `object`, `property` |
| `Identifier` | Variable name | `name` |
| `Literal` | Literal value | `value`, `raw` |
| `ObjectExpression` | Object literal | `properties` |
| `Property` | Object property | `key`, `value`, `method` |
| `ExportDefaultDeclaration` | Export default | `declaration` |
| `TSTypeAnnotation` | TypeScript type | `typeAnnotation` |
| `TSNumberKeyword` | `: number` | - |
| `TSStringKeyword` | `: string` | - |

---

## 6. Recommendations

### For CloudLang Compiler:

1. **Use `@typescript-eslint/typescript-estree`**
   - Most OCaml-friendly
   - Clean JSON, no circular refs
   - Standard ESTree format

2. **Node.js Bridge Script**
   - Create `tools/ts-to-ast.js` script
   - CloudLang compiler spawns Node.js subprocess
   - Pipe TypeScript → stdout JSON

3. **OCaml Deserialization**
   - Use `jsont` for type-safe parsing
   - Map ESTree types to CloudLang IR types
   - Handle TypeScript-specific nodes (`TSTypeAnnotation`, etc.)

4. **Closure Detection**
   - AST doesn't explicitly mark closures
   - Implement scope analysis in OCaml
   - Track free variables in arrow functions

### Example Integration:

```ocaml
(* cloudlang/lib/typescript_parser.ml *)

let parse_typescript_file (filepath : string) : Ast.t =
  let json_output = 
    let cmd = Printf.sprintf "node tools/ts-to-ast.js %s" filepath in
    let chan = Unix.open_process_in cmd in
    let json_str = In_channel.input_all chan in
    Unix.close_process_in chan |> ignore;
    json_str
  in
  let estree_ast = Jsont.decode estree_program_dec json_output in
  Estree_to_cloudlang.convert estree_ast
```

---

## 7. References

- **ESTree Spec**: https://github.com/estree/estree
- **typescript-estree Docs**: https://typescript-eslint.io/packages/typescript-estree
- **Babel Parser Docs**: https://babeljs.io/docs/babel-parser
- **AST Explorer** (interactive): https://astexplorer.net/
- **TypeScript Issue #61260**: Request for native JSON AST output (still open as of 2026)

---

## Appendix: ASCII Diagram of AST Transformation Flow

```
                     CloudLang Compiler Architecture
                     ================================

┌─────────────────────────────────────────────────────────────────┐
│                         INPUT                                    │
│                    TypeScript Source                             │
│                                                                   │
│   const cache = new Map();                                       │
│   const get = (key: string) => cache.get(key);                   │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
          ┌──────────────────────────────┐
          │  Node.js Subprocess          │
          │  (typescript-estree)         │
          │                              │
          │  parse(code, options)        │
          └──────────┬───────────────────┘
                     │
                     │ stdout: JSON (ESTree format)
                     ▼
          ┌──────────────────────────────┐
          │  OCaml: Yojson.Basic.from_   │
          │  string / jsont decode       │
          └──────────┬───────────────────┘
                     │
                     ▼
          ┌──────────────────────────────┐
          │  ESTree AST                  │
          │  (type-safe OCaml record)    │
          │                              │
          │  Program {                   │
          │    body: [                   │
          │      VariableDeclaration,    │
          │      VariableDeclaration     │
          │    ]                         │
          │  }                           │
          └──────────┬───────────────────┘
                     │
                     ▼
          ┌──────────────────────────────┐
          │  CloudLang AST               │
          │  (custom IR)                 │
          │                              │
          │  - Semantic analysis         │
          │  - Closure detection         │
          │  - Type inference            │
          └──────────┬───────────────────┘
                     │
                     ▼
          ┌──────────────────────────────┐
          │  CloudLang IR                │
          │  (intermediate repr.)        │
          └──────────┬───────────────────┘
                     │
                     ▼
          ┌──────────────────────────────┐
          │  Cloudflare Config           │
          │  (Workers, DO, R2, D1)       │
          └──────────────────────────────┘
```

---

**End of Research Document**
