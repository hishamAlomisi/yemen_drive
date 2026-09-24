# YemenDrive Customer App — AI Development Guide

**Purpose:** reference for AI-assisted changes in the customer Flutter app. Audited against checked-out source on 2026-09-23. This records observed project conventions; verify current source when files or contracts have changed.

## Scope and source of truth

- Project: `E:\Eqs\yemen_drive` (customer app). The driver app is a separate sibling project and is not described by this file.
- Read `README.md`, `lib/features/ARCHITECTURE.md`, relevant feature source, tests and the API contract documents before changing code. Some API documentation is aspirational or may lag implementation; the running API source and Postman contract take precedence for implemented behavior.
- Preserve existing user changes. Check `git status` and inspect the target diff before editing.

## ARCHITECTURE

- Flutter/Dart app organized by feature under `lib/features/` (`auth`, `ride`, `account`). App-wide wiring is in `lib/app/`; shared infrastructure is in `lib/core/`; reusable cross-feature presentation widgets/models are in `lib/shared/`.
- Each operation uses only the needed feature folders: `bindings`, `controllers`, `models`, `providers`, `repositories`, `views`, `widgets`. Keep UI composition in views/widgets, state/orchestration in GetX controllers, HTTP/platform access in providers, and domain-facing operations in repositories.
- Cross-feature application logic goes in `core` only when genuinely app-wide. Cross-feature presentation reuse goes in `shared`; feature-only widgets/models stay with that feature.
- Route definitions are grouped by feature and assembled into `AppPages.pages`. Register controllers/services in the relevant binding, not ad hoc from unrelated widgets.
- Legacy compatibility exports may remain for old imports; do not add new behavior to compatibility surfaces when the owning feature has a canonical implementation.

## CODING STYLE

- Dart SDK constraint is `>=3.6.0 <4.0.0`; Flutter lint rules come from `flutter_lints` with strict casts/inference/raw types and project rules such as explicit return types, no `dynamic` calls, no `print`, final locals, trailing commas and ordered directives.
- Follow nearby formatting and naming: `snake_case.dart` files, UpperCamelCase types, lowerCamelCase members, immutable request/response data where practical, explicit generic types at API/state boundaries.
- Use `GetxController` for feature state and `Obx` only around state-dependent UI. Dispose controllers, streams, subscriptions, map handles and text/focus controllers at their proper lifecycle boundary.
- Handle async/loading/error/empty states explicitly. Avoid unawaited requests, duplicate polling, swallowed errors and navigation through stale widget contexts.
- Add user-facing labels to `AppTranslations` (`ar_SA` and English locale where supported) and use `.tr`; avoid hard-coded UI strings outside established cases.

## MODEL CONVENTIONS

- Keep API request/response and view models in the owning feature’s `models/`; shared models belong in `lib/shared/models` only if multiple unrelated features use them.
- Parse untrusted JSON defensively at the provider/repository boundary. Preserve nullability and identifier semantics from the API; do not silently default critical payment, ride-status, identity or location fields.
- Keep API DTOs distinct from widget-only view state when their lifecycles/meaning differ. Do not pass raw response maps through the UI.
- Customer app has no direct SQL/database layer. Server persistence is authoritative; local preferences/session values must not be treated as financial truth.

## API CONVENTIONS

- Use the shared Dio `ApiClient` (`lib/core/network/api_client.dart`) for HTTP. It supplies JSON headers, Arabic language preference, bearer token, timeout policy and standard problem parsing. Reuse `ApiEndpoints` where a named route exists.
- For regular operations, follow the current execute envelope `{ model, operation, data }` and parse `ApiResult`/`ApiSuccess`/`ApiFailure` as nearby repositories do. Keep feature calls in their provider/repository, not a widget.
- Some API features use dedicated REST paths or SignalR; match the implemented server endpoint and its response contract. Do not assume every proposed endpoint in `docs/aspnet_api_contract.md` exists.
- Treat server responses as source of truth for wallet balance, ledger/payment status, ride eligibility, cancellation decisions and service availability. A client button must never create a wallet/ledger balance directly.
- Use `AuthSessionService` and `SecureStorageService` for authentication tokens. Do not persist tokens in ordinary preferences, log tokens/PII, or embed server/payment secrets in Dart, assets or build arguments.
- Google Maps SDK keys embedded in the mobile package are extractable by design: use only appropriately restricted client keys. Private Places/Routes/Geocoding credentials belong on the server and should be called through server endpoints.
- For SignalR tracking, respect server authorization and reconnect lifecycle. Re-fetch authoritative ride state after reconnect rather than trusting a stale event alone.

## UI / DESIGN SYSTEM

- Design tokens live in `lib/app/theme/` (`AppColors`, palette, spacing/radius and `AppTheme`). Reuse shared components under `lib/shared/widgets` before introducing another button/card/field/scaffold/map implementation.
- App is Arabic-first RTL with `GetMaterialApp` localization; use directional alignment/padding (`AlignmentDirectional`, `EdgeInsetsDirectional`) and test both locale/direction and narrow screen behavior.
- Use theme `ColorScheme` and tokens for colors/spacing/radius. Preserve light/dark behavior and semantic success/warning/error colors; do not hardcode arbitrary shades into one screen.
- Use `AdaptiveContent` and responsive helpers for wide screens. Long content/forms must scroll and accommodate keyboard insets.
- Maps: use the shared map abstraction/widgets where available; keep coordinate data for map behavior but show resolved human-readable place labels in customer-facing text. Handle no-key/offline/provider errors without fabricated coordinates or routes.
- Route navigation uses route constants and feature route lists; avoid direct route strings or navigation decisions hidden in reusable visual-only widgets.

## DATABASE CONVENTIONS

- Not applicable inside this Flutter repository: no client-managed SQL schema/migrations. Do not create a second source of financial or ride truth locally.
- When a feature needs persistence, use the API contract and server-owned records. Device storage is for user preferences and secure session tokens only, following the relevant `core/storage` service.
- Database changes belong to the API/database repository, require a migration and server-side invariants, and must not be inferred from a Flutter JSON field alone.

## TESTING AND CHANGE CHECKLIST

- Run `flutter analyze` and `flutter test` from the app root. Add focused unit/widget tests for state transitions, parsers, validation, loading/error paths and navigation as appropriate.
- Keep smoke tests deterministic and offline; inject fakes/mocks rather than requiring a live API, map provider, dialer or user account.
- For ride/payment/safety flows, check duplicate taps, stale state, retry behavior, route/back handling, authorization failures and app lifecycle/reconnect behavior. Do not make real calls, payments, or contact third parties during automated tests.
- Before handoff, state files changed, checks run, API dependency/contract assumptions and any manual device testing still needed. Do not claim full integration coverage based on a widget smoke test.

## NON-NEGOTIABLE PROJECT RULES

- Preserve server ownership of ride, payment, wallet and service-availability decisions. The client may present or request an operation, but must not manufacture authoritative outcomes.
- Keep feature code within its owning feature and preserve the provider/repository/controller/view boundaries used by neighboring code.
- Preserve existing user changes. Inspect repository status and the relevant diff before editing; do not overwrite unrelated work.
- Never place authentication tokens, private payment credentials or server-only provider keys in source, assets, ordinary preferences or logs.

## SOURCE PRIORITY

- For implemented client behavior, use current Dart source and tests as primary evidence. Read the relevant API implementation/contract and Postman material when interpreting server behavior; documentation may lag implementation.
- For server-owned behavior, the running API implementation and its current response contract are authoritative over client assumptions or older prose documentation.
- Treat generated/build artifacts and preview documents as secondary evidence unless the feature explicitly consumes them at runtime.
- If source, tests and API contract disagree, record the mismatch and do not silently encode one interpretation as fact.

## PATTERN CONSISTENCY

- Follow the canonical feature structure in `lib/features/` and nearby implementations; use bindings for feature dependency registration and repositories/providers for data access.
- Reuse shared API, localization, theme, responsive and widget abstractions before adding parallel implementations.
- Compatibility route/export surfaces exist (for example legacy route constants and compatibility exports). Keep them only where needed for existing imports/navigation; put new behavior in the owning feature's canonical implementation.
- Where patterns differ between older and newer feature code, match the actively maintained neighboring flow and document the exception rather than broadening the older pattern.

## STATE MANAGEMENT

- GetX is the established app state and dependency-management approach: feature controllers commonly extend `GetxController`, expose observable state, and are registered through feature bindings; app-wide services are initialized in `InitialBinding`.
- Use `Obx` for reactive view regions and keep async orchestration and state transitions in controllers/repositories rather than widgets.
- Respect lifecycle cleanup for subscriptions, timers, map controllers, text/focus controllers and other owned resources. Stop polling/listeners when their state or screen lifecycle ends.
- Do not add another state-management package or parallel global state store for a local feature without an existing project pattern requiring it.

## BACKWARD COMPATIBILITY

- Preserve established route names, API payload/response semantics, persisted preference keys and legacy exports when changing their implementation.
- If an API contract or route must change, update all affected client call sites and tests together; retain compatibility handling only when the server/client contract actually requires it.
- Do not reinterpret missing/null fields as success for critical ride, payment, identity or location state. Make compatibility defaults explicit and narrowly scoped.

## SECURITY

- Store session tokens through `SecureStorageService` and use `AuthSessionService` for session lifecycle. Do not copy tokens into ordinary preferences or diagnostic output.
- Do not log credentials, access tokens, payment details, precise personal location or other sensitive data. Treat API errors and user-provided text as potentially sensitive.
- Mobile Maps SDK keys are package-extractable; use client-restricted keys only. Private Places/Routes/Geocoding credentials and privileged operations remain server-side.
- Keep authorization decisions and validation on the API. Hiding/disabling a client control is not a security boundary.

## FINANCIAL INVARIANTS

- API responses are authoritative for wallet balance, ledger entries, payment status, fare and refund/cancellation settlement. Never update a balance by locally adding/subtracting an assumed transaction as if it were persisted.
- A client action may submit a payment/cash-collection request or approval, but must not directly create wallet credits/debits or assert settlement without the server result.
- Preserve operation identity/idempotency information where the API contract supplies it, and guard user actions against duplicate submission while a request is in flight.
- Keep incomplete, rejected, pending and successful payment states distinct; do not infer ride completion solely from a local payment-screen state.

## LOGGING AND OBSERVABILITY

- The shared `ApiClient` converts transport/server failures into the project's `ApiFailure`/problem-details result pattern; preserve that information through repository/controller layers and show an appropriate user-facing state.
- Existing code contains limited `debugPrint` diagnostics, but no project-wide structured logging convention is evident. Follow a nearby established diagnostic pattern only when necessary; never add sensitive values to logs.
- Do not swallow errors or report success after a failed request. Where useful to the user, expose loading, failure and retry states in the UI.

## CHANGE MANAGEMENT

- Before editing, inspect the repository state and the target files/diff; preserve unrelated and uncommitted user work.
- Trace a behavior change across the affected view, controller, repository/provider, model, route/binding and API contract rather than changing only the visible widget.
- Keep changes scoped to the customer app unless a server or driver-app change is explicitly requested; document cross-repository dependencies instead of silently modifying them.
- Update focused tests and user-facing translations when behavior or copy changes. Report checks run and any live API/device verification that remains outstanding.

## DEFINITION OF DONE

- The change follows existing feature boundaries, GetX lifecycle and shared design/localization conventions, and does not introduce a competing implementation for an existing capability.
- Relevant request/response parsing and success, loading, empty, error, retry and duplicate-action paths are addressed; server-owned ride/payment/wallet state remains authoritative.
- Focused tests pass, and `flutter analyze`/`flutter test` are run when the environment permits. Any unrun check or required manual device/API verification is stated explicitly.
- The handoff identifies changed files, behavior, checks performed, contract assumptions and known limitations; no claim of live integration is made without actually testing it.
