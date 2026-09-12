# Feature organization

Each user operation lives under its own feature directory. Use only the
folders needed by that operation:

- `bindings`: GetX dependency registration for the operation.
- `controllers`: UI state and orchestration for the operation.
- `models`: operation-specific request, response, and view models.
- `providers`: direct HTTP, storage, or platform access.
- `repositories`: domain-facing data contracts and implementations.
- `views`: pages and screens.
- `widgets`: widgets used only by that operation.

Cross-feature code belongs in `core` only when it is application-wide, or in
`shared` only when it is presentation code reused by unrelated features.
Do not add new behavior to compatibility exports under `ride/data`; new code
must import the repository from its owning feature directory.

Examples:

- `auth/login`
- `auth/registration`
- `auth/password_reset`
- `auth/location_permission`
- `ride/location_selection`
- `ride/vehicle_selection`
- `ride/negotiation`
- `account/change_password`
- `account/contact`
- `account/delete_account`
