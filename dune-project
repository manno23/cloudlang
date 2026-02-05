(lang dune 3.20)
(authors "Jason Manning <manno@j9m>")
(maintainers "Jason Manning <manno@j9m>")
(license GPL-3.0-or-later)
(source (github username/reponame))

(name cloudlang)
(generate_opam_files true)
(package
 (name cloudlang)
 (synopsis "CF Graph Compiler")
  (depends
     stdio
     menhirLib
      ocaml))
