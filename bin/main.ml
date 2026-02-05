open Cloudlang

let read_file filename =
  let ch = open_in filename in
  let s = really_input_string ch (in_channel_length ch) in
  close_in ch;
  s

let () =
  if Array.length Sys.argv < 2 then
    print_endline "Usage: cloudlang <file.cl>"
  else
    let filename = Sys.argv.(1) in
    let source = read_file filename in
    match parse source with
    | Error e -> Printf.printf "Parse error: %s\n" e
    | Ok ast ->
      match typecheck ast with
      | Error e -> Printf.printf "Type error: %s\n" e
      | Ok typed_ast ->
        match compile typed_ast with
        | Error e -> Printf.printf "Compile error: %s\n" e
        | Ok ir ->
          let output = generate ir in
          print_endline output
