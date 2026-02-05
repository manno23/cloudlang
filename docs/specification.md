# CloudLang Worker Graph Compiler Specification (Draft)

## 1. Purpose
This document defines a research-driven specification for the CloudLang compiler, with an emphasis on modeling Cloudflare Workers as typed nodes in a distributed dataflow graph. The design is test-driven: tests and example outputs define expected behavior, and implementation follows those specifications.

## 2. Research Team Charter
The following research team roles establish ownership of the specification and its validation artifacts. The team is virtual; each role maps to a concrete set of deliverables and reviews.

### 2.1 Roles and Responsibilities
- **Language Architect**
  - Defines the surface language and core semantics.
  - Owns the formal model for effects, bindings, and triggers.
  - Produces and maintains the normative language spec and effect rules.
- **IR & Compiler Pipeline Lead**
  - Owns the graph IR and all lowering passes (front-end to graph IR).
  - Defines partitioning heuristics and correctness invariants for graph extraction.
  - Produces IR reference documentation and invariants.
- **Cloudflare Runtime Integrations Lead**
  - Defines output targets (Workers, Durable Objects, queues, R2, D1, KV).
  - Owns generated configuration (wrangler bindings and routing glue).
  - Produces runtime integration tests and example outputs.
- **Testing & Verification Lead**
  - Owns the test harness and test-driven development plan.
  - Defines test taxonomies, coverage goals, and regression workflows.
  - Maintains golden outputs and snapshot tests.
- **Documentation & Examples Lead**
  - Maintains examples and reference docs.
  - Produces tutorial and narrative documentation aligned with tests.

### 2.2 Operating Principles
- **Tests define design**: new features require tests that capture desired behavior.
- **Traceability**: each spec section references tests that establish it.
- **Minimal viable semantics first**: grow the language from a minimal core.

## 3. Project Goals
1. **Model Workers as capability-safe, typed graph nodes** with explicit triggers, bindings, and effect signatures.
2. **Compile an ML-like source language** into a graph IR with explicit edges representing inter-node communication, storage usage, and event flow.
3. **Generate Cloudflare-compatible artifacts** (Workers, Durable Objects, queues, storage bindings) along with the necessary wiring configuration.
4. **Provide a test-driven compiler pipeline** where each pass has explicit, testable contracts.
5. **Ensure deployable correctness** through deterministic, reproducible outputs.

## 4. Project Layout (Repository Structure)
```
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
└── examples/              # Example CloudLang programs
```

## 5. Core Conceptual Model
### 5.1 Worker Nodes
A Worker is a typed node in a distributed dataflow graph:
- **Triggers** describe how the node is invoked (fetch, scheduled, queue, DO message).
- **Bindings** describe capabilities (KV, R2, D1, DO, queues, secrets, services).
- **Effects** describe which capabilities are required.

### 5.2 Graph IR (Conceptual)
The IR represents a graph of nodes and edges:
- **Nodes**: include triggers, bindings, effects, and code references.
- **Edges**: represent service calls, storage access, and event emission.

This IR is the target of all front-end compilation and the source of backend generation.

## 6. Compiler Pipeline (Methodological Plan)
This pipeline is driven by research in language and compiler design, with correctness defined by test artifacts.

### 6.1 Frontend (Parsing + Typing)
- Parse ML-like syntax into an AST.
- Typecheck with explicit effect annotations (or inferred effect rows as a later phase).
- Produce a typed AST with explicit effect summaries for each function.

### 6.2 Closure Conversion
- Lift nested functions into top-level functions.
- Convert closures into explicit environment records.
- Decide storage for closure environments (argument passing vs persistent storage).

### 6.3 Partitioning (“Worker Splitter”)
- Map typed functions into graph nodes.
- Extract inter-node edges for RPC/service bindings, queues, and storage usage.
- Partitioning policy is explicitly tested (see TDD plan).

### 6.4 IR Lowering
- Emit graph IR from partitioned units.
- Validate invariants:
  - nodes expose all required bindings.
  - edges refer to valid node IDs.
  - effect sets match binding requirements.

### 6.5 Backend Code Generation
- Emit Worker/DO JS (or wasm with JS glue).
- Emit wrangler configuration and routing glue.
- Emit client/server stubs for inter-node RPC.

## 7. Testing Harness
### 7.1 Test Taxonomy
- **Unit tests**: compiler passes, AST transforms, and effect inference.
- **Integration tests**: full pipeline outputs and wrangler configs.
- **Cram tests**: CLI usage and end-to-end invocation.

### 7.2 Golden Output Tests
- Store expected IR and generated config as golden files.
- Run diff-based snapshot tests for regressions.

### 7.3 Property Tests (Optional Future Work)
- Use property-based tests for effect inference and graph invariants.

## 8. Test-Driven Development (TDD) Strategy
### 8.1 TDD Workflow
1. Write a failing test that describes the new feature.
2. Implement minimal functionality to satisfy the test.
3. Refactor only after tests pass.

### 8.2 Test-Defined Design Examples
- **Example: Worker Node Extraction**
  - Input: source file with annotated handlers.
  - Output: graph IR with nodes and edges.
- **Example: Effect Enforcement**
  - Input: function using KV without binding annotation.
  - Output: compile error with precise location and message.
- **Example: Service Binding Generation**
  - Input: call to another node.
  - Output: generated client stub and binding in wrangler config.

## 9. MVP Scope (Phase 1)
- Top-level functions only (no nested lambdas).
- Explicit node annotations (no automatic partitioning yet).
- Explicit effect and binding declarations.
- Graph IR and backend stubs for Workers and service bindings.

## 10. Future Scope (Phase 2+)
- Effect inference and row polymorphism.
- Automatic partitioning heuristics.
- Durable Object–based closure environments.
- WASM target with explicit ABI.

## 11. Example Outputs (Normative)
### 11.1 Example: Minimal Worker
**Input**: a single fetch handler with KV usage.
**Expected Output**:
- Graph IR node with `Fetch` trigger, `KV` binding, and `E_KV` effect.
- Generated configuration containing a KV binding.

### 11.2 Example: RPC Call
**Input**: Node A calls Node B.
**Expected Output**:
- Edge `Calls` from A to B.
- Generated service binding in A.
- Generated RPC handler in B.

### 11.3 Example: Closure Translation (Two Workers + R2)
**Input**: A program with a closure (`make_greeter`) captured by a handler and an export of `handler`.
**Expected Output**:
- Two workers (`edge-worker`, `compute-worker`), with a route assigned to `edge-worker`.
- An R2 bucket named `app-data`.
- Generated worker scripts that model request input and response output.
- A generated configuration that includes both workers and the R2 bucket.

## 12. Definition of Done
- All tests pass.
- `dune build` succeeds.
- `dune fmt` is clean.
- All new features documented with examples and tests.

## 13. References (Research Summary)
- **Algebraic effects and handlers** for effect tracking and capability isolation.
- **Graph IR design** from distributed systems compilers.
- **Closure conversion** from functional compiler literature.
- **Capability-based security** to ensure bindings are explicit.

This section establishes the research basis but is intentionally high-level. Detailed bibliographic references will be added as the research team produces them.
