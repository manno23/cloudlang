(** ESTree-compatible AST subset for TypeScript.

    This represents the minimal set of TypeScript constructs needed for
    closure analysis and Worker decomposition. Node types follow the ESTree
    specification used by @typescript-eslint/typescript-estree. *)

type var_kind = Const | Let | Var

type literal_value =
  | LString of string
  | LNumber of float
  | LBool of bool
  | LNull
  | LUndefined

(** A single AST node. The variant name matches the ESTree "type" field. *)
type node =
  | Program of { body : node list }
  | VariableDeclaration of { kind : var_kind; declarations : node list }
  | VariableDeclarator of { id : node; init : node option }
  | Identifier of { name : string }
  | Literal of { value : literal_value }
  | ArrowFunctionExpression of {
      params : node list;
      body : node;
      async_ : bool;
    }
  | BlockStatement of { body : node list }
  | ReturnStatement of { argument : node option }
  | IfStatement of { test : node; consequent : node; alternate : node option }
  | ExpressionStatement of { expression : node }
  | CallExpression of { callee : node; arguments : node list }
  | MemberExpression of { object_ : node; property : node }
  | NewExpression of { callee : node; arguments : node list }
  | BinaryExpression of { operator : string; left : node; right : node }
  | LogicalExpression of { operator : string; left : node; right : node }
  | ExportNamedDeclaration of { specifiers : node list }
  | ExportSpecifier of { local : node }
