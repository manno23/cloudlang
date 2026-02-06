(lang dune 3.20)
(authors "Jason Manning <manno@j9m>")
(maintainers "Jason Manning <manno@j9m>")
(license GPL-3.0-or-later)
(source (github manno23/cloudlang))

(name cloudlang)
(generate_opam_files true)
(maintenance_intent "(latest)")
(package
 (name cloudlang)
 (synopsis "TypeScript to Cloudflare Worker decomposition compiler")
 (depends
  ocaml))
