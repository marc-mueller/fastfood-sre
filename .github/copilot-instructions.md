# Custom instructions

> **Project tools:** `fastfoodmcp` and `kubernetes` (local MCP).
> **Primary goal:** Answer questions and and fix issues **using fastfoodmcp tools** whenever they apply. If you need information from the live system or if you need to fix issues in the cluster **use kubernetes tool**. Prefer tool calls over guessing.

## When to call which tool

* **Errors**

  * `ExplainError(code)` → any mention of an internal error code (e.g., E2145, P5001) or “what does this error mean?”
  * `SearchErrors(query, limit)` → user gives a log line/keyword but not a code, or `ExplainError` returns “not found.”
  * `SuggestFix(code)` → the user asks for concrete remediation steps or a runbook summary.
* **Services (system awareness)**

  * `GetService(name)` → user asks what a service does, repo, language, or its API list.
  * `ListDependencies(name, direction)`

    * `outbound` → “what does X depend on?”
    * `inbound` → “who depends on X?”
  * `FindEndpoint(name, [path])` → user asks about available routes or filters by a path fragment.
  * `ServiceOwner(name)` → user asks for owners, Slack channel, or runbook.
* **Feature flags**

  * `ListFlags([service])` → enumerate flags (optionally scoped to a service).
  * `GetFlag(key)` → full definition and environments.
  * `FlagStatus(key, environment)` → resolve the *effective* value in `dev | staging | prod`.

## Execution rules

1. **Prefer tools** over assumptions for anything about errors, services/dependencies, feature flags.
2. If a lookup fails, **immediately try the fuzzy/backup tool** (e.g., `SearchErrors` after a miss; or suggest top 3 close service names from the response).
3. **Surface links** (runbooks) from tool responses when proposing steps.
4. When writing code/tests that depend on a **feature flag**, call `FlagStatus` first and generate **parameterized tests** or branches for true/false (or multivariants).
5. When planning a change, call `ListDependencies` (both directions if risk is discussed) and name owners via `ServiceOwner` for review routing.
6. Keep answers **actionable**: summarize tool result → concrete next steps → (optionally) code or commands.
7. For every issue, create a markdown file with a timestamp under /resolvedissues documenting the resolved steps as well as a post mortem.