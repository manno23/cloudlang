module A = Cloudlang.Ast

let has_substr s sub =
  let len_s = String.length s in
  let len_sub = String.length sub in
  if len_sub > len_s then false
  else
    let found = ref false in
    for i = 0 to len_s - len_sub do
      if String.sub s i len_sub = sub then found := true
    done;
    !found

let id name = A.Identifier { name }
let str s = A.Literal { value = A.LString s }
let undef = A.Literal { value = A.LUndefined }

let const_decl name init =
  A.VariableDeclaration
    {
      kind = A.Const;
      declarations = [ A.VariableDeclarator { id = id name; init } ];
    }

let arrow params body =
  A.ArrowFunctionExpression { params; body; async_ = false }

let call callee arguments = A.CallExpression { callee; arguments }
let member obj prop = A.MemberExpression { object_ = obj; property = id prop }
let expr_stmt e = A.ExpressionStatement { expression = e }
let block stmts = A.BlockStatement { body = stmts }
let ret e = A.ReturnStatement { argument = Some e }

let if_ test consequent alternate =
  A.IfStatement { test; consequent; alternate }

let bin op left right = A.BinaryExpression { operator = op; left; right }
let logic op left right = A.LogicalExpression { operator = op; left; right }
let new_ callee arguments = A.NewExpression { callee; arguments }

let export_named names =
  A.ExportNamedDeclaration
    {
      specifiers = List.map (fun n -> A.ExportSpecifier { local = id n }) names;
    }

let build_kv_store_ast () : A.node =
  A.Program
    {
      body =
        [
          const_decl "store" (Some (new_ (id "Map") []));
          const_decl "put"
            (Some
               (arrow
                  [ id "key"; id "value" ]
                  (block
                     [
                       expr_stmt
                         (call
                            (member (id "store") "set")
                            [ id "key"; id "value" ]);
                     ])));
          const_decl "get"
            (Some
               (arrow
                  [ id "key" ]
                  (block
                     [ ret (call (member (id "store") "get") [ id "key" ]) ])));
          const_decl "cache" (Some (new_ (id "Map") []));
          const_decl "cachedGet"
            (Some
               (arrow
                  [ id "key" ]
                  (block
                     [
                       const_decl "hit"
                         (Some (call (member (id "cache") "get") [ id "key" ]));
                       if_ (id "hit") (ret (id "hit")) None;
                       const_decl "result" (Some (call (id "get") [ id "key" ]));
                       if_ (id "result")
                         (block
                            [
                              expr_stmt
                                (call
                                   (member (id "cache") "set")
                                   [ id "key"; id "result" ]);
                              ret (id "result");
                            ])
                         None;
                       ret undef;
                     ])));
          const_decl "handleRequest"
            (Some
               (arrow
                  [ id "method"; id "key"; id "value" ]
                  (block
                     [
                       if_
                         (bin "===" (id "method") (str "GET"))
                         (ret
                            (logic "??"
                               (call (id "cachedGet") [ id "key" ])
                               (str "NOT_FOUND")))
                         None;
                       if_
                         (logic "&&"
                            (bin "===" (id "method") (str "PUT"))
                            (id "value"))
                         (block
                            [
                              expr_stmt
                                (call (id "put") [ id "key"; id "value" ]);
                              ret (str "OK");
                            ])
                         None;
                       ret (str "BAD_REQUEST");
                     ])));
          export_named [ "handleRequest" ];
        ];
    }

let analyze_exn program =
  match Cloudlang.analyze program with
  | Ok analysis -> analysis
  | Error e -> failwith (Printf.sprintf "analyze failed: %s" e)

let compile_exn analysis =
  match Cloudlang.compile analysis with
  | Ok config -> config
  | Error e -> failwith (Printf.sprintf "compile failed: %s" e)
