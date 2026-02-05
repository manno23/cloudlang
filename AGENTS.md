# CloudLang Agent Guidelines

## Project Overview

CloudLang is a functional language compiler that targets Cloudflare infrastructure configurations (Workers, Durable Objects, R2, D1, etc.). The compiler produces an intermediate representation (IR) that can be translated to Cloudflare-specific configuration formats.

This is an OCaml project using the Dune build system. The codebase follows standard OCaml conventions with additional project-specific patterns for compiler construction.

## Build Commands

### Core Build Commands
\`\`\`bash
# Build the entire project
dune build

# Build and run the main executable
dune exec cloudlang

# Build in watch mode (requires \`dune build --watch\` or \`dune build -w\`)
dune build -w

# Build only the library
dune build lib

# Build only the executable
dune build bin

# Clean build artifacts
dune clean
\`\`\`

### Development Commands
\`\`\`bash
# Start utop with the library loaded
dune utop lib

# Run the compiler with a test file
dune exec cloudlang -- path/to/file.cl

# Generate OPAM files (if dune-project changes)
dune build @install
\`\`\`

## Test Commands

### Running Tests
\`\`\`bash
# Run all tests
dune runtest

# Run a specific test suite
dune runtest test/

# Run a single test by name (if using alcotest)
dune exec test/test_cloudlang.exe -- --test <test-name>

# Run tests with coverage (requires bisect_ppx)
dune runtest --instrument-with bisect_ppx --force
\`\`\`

### Writing Tests
- Tests reside in \`test/\` directory
- Use Alcotest framework for unit tests
- Use Cram tests for integration/CLI tests
- Test files should mirror library structure: \`test/unit/\` for unit tests, \`test/integration/\` for integration tests

## Linting and Formatting

### Code Formatting
\`\`\`bash
# Format all OCaml files in the project
dune fmt

# Check formatting without applying changes
dune fmt --check

# Format a specific file
ocamlformat --inplace path/to/file.ml
\`\`\`

### Linting
\`\`\`bash
# Run OCaml Lint (ocaml-lint) if configured
# Typically integrated via dune build @lint
dune build @lint

# Type-check the entire project
dune build @typecheck
\`\`\`

### Pre-commit Hooks
Consider adding pre-commit hooks that run:
- \`dune fmt --check\`
- \`dune build\`
- \`dune runtest\`

## Code Style Guidelines

### Imports (\`open\`)
- Use \`open\` sparingly; prefer qualified access for modules outside the current library
- Avoid opening multiple modules that could cause name collisions
- When opening modules, place \`open\` statements at the top of the file after the module signature
- Use local opens (\`let open Module in ...\`) for scoped access

### Module Structure
- Each significant compiler phase should have its own module
- Module names should be descriptive: \`Parser\`, \`Typechecker\`, \`Ir\`, \`Codegen\`
- Use module signatures (\`module type\`) to define interfaces
- Implement functors for configurable components

### Types
- Use algebraic data types (ADTs) to represent language constructs
- Prefer records over tuples for data with multiple fields
- Use type abbreviations (\`type t = ...\`) for the main type of a module
- Make types exhaustive and use the \`[@@deriving]\` annotations for serialization, comparison, etc.

### Naming Conventions
- **Modules**: \`PascalCase\` (e.g., \`Ast\`, \`Semantic_analysis\`)
- **Functions/variables**: \`snake_case\` (e.g., \`parse_expression\`, \`type_env\`)
- **Types**: \`snake_case\` or \`CamelCase\` depending on context (ADT constructors use \`CamelCase\`)
- **Constants**: \`UPPER_SNAKE_CASE\` for module-level constants
- **Files**: \`snake_case.ml\` matching module name

### Error Handling
- Use \`result\` type (\`('a, 'b) result\`) for recoverable errors
- Use exceptions only for unrecoverable errors (e.g., assertion failures)
- Define custom error types for each compiler phase
- Provide helpful error messages with source locations
- Use the \`pp\` (pretty-print) functions for error display

### Pattern Matching
- Make pattern matches exhaustive; use wildcard \`_\` only when intentional
- Use \`[@warning "-8"]\` to disable unused pattern variable warnings when appropriate
- Prefer pattern matching over \`if\`/\`else\` for complex conditionals
- Use \`function\` syntax for single-argument pattern matching

### Mutability
- Avoid mutable state; use pure functions where possible
- When mutation is necessary, use \`ref\` cells or mutable record fields
- Document why mutation is needed

## Compiler-Specific Patterns

### AST Design
- Define AST in a separate module (\`Ast\`) with position annotations
- Use polymorphic variants for extensibility if needed
- Include visitor patterns for tree traversal

### Intermediate Representation (IR)
- IR should be simpler than AST, closer to target semantics
- Define IR as a separate set of types in module \`Ir\`
- Include conversion functions (\`Ast_to_ir\`)

### Cloudflare Target Generation
- Create separate modules for each Cloudflare service: \`Worker_gen\`, \`Durable_object_gen\`, \`R2_gen\`, \`D1_gen\`
- Output should be JSON or TypeScript configuration compatible with Cloudflare APIs
- Use \`jsont\` library for JSON serialization

## Project Structure

\`\`\`
cloudlang/
├── bin/                    # Executable entry point
│   └── main.ml            # CLI parsing and orchestration
├── lib/                   # Core compiler library
│   ├── ast.ml            # Abstract syntax tree
│   ├── parser.ml         # Parser (using Menhir)
│   ├── typechecker.ml    # Type checking
│   ├── ir.ml             # Intermediate representation
│   ├── codegen/          # Code generation modules
│   └── cloudlang.ml      # Library interface
├── test/                  # Test suites
│   ├── unit/             # Unit tests
│   ├── integration/      # Integration tests
│   └── cram/             # Cram tests for CLI
└── examples/             # Example CloudLang programs
\`\`\`

## Agent Instructions

When working on this project:

1. **Always run tests** after making changes: \`dune runtest\`
2. **Format code** before committing: \`dune fmt\`
3. **Maintain type safety** - ensure \`dune build\` succeeds
4. **Follow the compiler architecture** - new phases should follow existing patterns
5. **Add tests** for new functionality
6. **Update documentation** in relevant \`.mli\` files
7. **Use existing libraries** - check \`dune-project\` for dependencies before adding new ones

## Dependency Management

- Dependencies are specified in \`dune-project\` and \`cloudlang.opam\`
- Add new dependencies via \`(depends ...)\` in \`dune-project\`
- Run \`opam install . --deps-only\` to install dependencies

## Common Pitfalls

- **Cyclic dependencies**: Keep module dependencies acyclic; use \`dune build\` to detect
- **Large files**: Split modules when they exceed 500 lines
- **Performance**: Use profiling (\`dune build --profile release\`) for performance-critical code
- **Error messages**: Always include source locations in error messages

## Quick Reference

| Command | Purpose |
|---------|---------|
| \`dune build\` | Build project |
| \`dune runtest\` | Run tests |
| \`dune fmt\` | Format code |
| \`dune exec cloudlang\` | Run compiler |
| \`dune utop lib\` | REPL with library |
| \`dune clean\` | Clean build |

*Last updated: 2025-02-05*
