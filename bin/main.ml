let () =
  if Array.length Sys.argv < 2 then
    print_endline
      "Usage: cloudlang <file.ts>\n\n\
       Decomposes a TypeScript program into Cloudflare Workers.\n\n\
       Currently expects a JSON ESTree AST on stdin.\n\
       (Direct .ts parsing via typescript-estree bridge is planned.)"
  else
    (* TODO: implement JSON AST ingestion from typescript-estree.
       For now the CLI is a placeholder; the real pipeline is exercised
       via the test suite which constructs the AST programmatically. *)
    let _filename = Sys.argv.(1) in
    Printf.printf
      "cloudlang: .ts file parsing not yet implemented.\n\
       Run `dune runtest` to see the pipeline in action.\n"
