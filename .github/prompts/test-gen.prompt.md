---
description: Generate tests following project conventions with arrange/act/assert structure
argument-hint: Select code or name the module to test
agent: agent
tools: [editFiles, runCommands, codebase]
---

# Generate Tests

Generate tests for the selected code following project conventions.

1. Use the project test framework: `custom bash (run_simple_tests.sh)`.
2. Mirror the source file path in the test directory.
3. Cover:
   - The main success path
   - At least one error/edge case
   - Boundary conditions if applicable
4. Follow the arrange/act/assert pattern.
5. Use descriptive test names: `"should <expected behaviour> when <condition>"`.
6. Mock external dependencies but not the module under test.
7. Run `bash tests/run_simple_tests.sh` after generating to verify tests pass.

Do not modify the source code — only create or update test files.
