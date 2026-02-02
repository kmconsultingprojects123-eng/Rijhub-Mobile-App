
/// Lightweight adapter/extensions to satisfy generated code's calls like
/// `context.pushNamed(...)`, `context.pop()`, and `context.go(...)`.
/// These map to `Navigator` methods as a safe stop-gap while you fix or pin
/// `go_router`/router mismatches. Keep implementations minimal to avoid logic changes.


// This file intentionally left minimal — we avoid defining navigation extension
// members that conflict with `go_router`'s own BuildContext extensions (such
// as pushNamed, go, pop). Generated code imports `flutter_flow_util.dart`,
// which now re-exports `go_router`, so use the package's helpers instead.
//
// If you absolutely need Navigator-based fallbacks, add uniquely named
// helpers (e.g., ffPushNamed) and update call sites. Keeping this file empty
// prevents ambiguous-extension diagnostics.
