# CloudLang

CloudLang is an experimental compiler that decomposes TypeScript closures into Cloudflare Worker resources and bindings.

## Status

This project is an early-stage prototype.

Current pipeline:
1. Build or ingest an ESTree-compatible AST.
2. Run scope analysis to identify closures, free variables, and exports.
3. Decompose closures into Worker groups based on shared mutable state.
4. Emit an intermediate representation (IR) and generated Worker artifacts.

## Development

- `dune build`
- `dune runtest`
- `dune fmt`

## Repository Layout

- `lib/`: compiler library modules
- `bin/`: CLI entry point
- `test/`: tests
- `examples/`: sample source files
