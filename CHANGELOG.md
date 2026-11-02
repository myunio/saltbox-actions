# Changelog

## Unreleased

- `enforce_confirm`: when on, an agent's call to a `:confirm` action is refused with
  `confirmation_required` unless the app's `config.confirm` hook approves it. Off by
  default, which keeps `:confirm` as advice to agents.
- `Caller#confirm!(action)` applies another action's `connections` rule inside a running action.

## 0.1.0 (unreleased)

- Each call gets its own deep copy of an argument's default.
- The API encodes the body once, so a string body arrives as a JSON string.

- MCP and RubyLLM send `false` and `null` bodies as JSON; only `head` reads "Done." (`FrontDoor::EMPTY`).
- Argument defaults are checked against the schema and satisfy a required input.
- `Invocation#invocation_id` stays readable in a deferred `after_change`.

- A change runs in its own savepoint, so a failure rolls back inside a caller's transaction.
- `after_change` runs once every enclosing transaction commits, and never on rollback.
- `render json: false` and `render json: nil` send that JSON; `Result#empty?` marks `head`.
- A declared `permission` replaces the policy's role question (`permitted?`) rather than adding to it.
- Argument defaults are filled in at run time.
- The registry shared example works with `every_file_an_action` off.

- For apps whose names were public first: `action_name`, `title`, `description` and `cli`
  declarations, `argument` descriptions and JSON Schema keywords.
- A `permission` gate (`any_of`, `:everyone`) with `config.permissions_held`, and
  `enforce_permissions` to let it decide only the actions list.
- `error_format :type` and `result_format :envelope`, `render meta:`, `Result#meta`.
- `default_connections`, `every_file_an_action`, `validate_arguments`; app error
  mappings are checked before the gem's own.

- Extracted from an internal application's action layer.
- Core: naming, declarations, input schema from policy-permitted columns, argument
  checks, the catalogue, rendering, permitting, invocation, registry boot checks,
  the front door (find_action and run tools) and the finder.
- Authorization adapters for Pundit and ActionPolicy.
- Surface adapters: MCP (streamable HTTP), RubyLLM tools, and a controller concern
  for /api/v1/actions.
- Hooks for the app's tenancy, audit, change publishing, feature flags, areas,
  error mapping and per-connection access.
- `returns` output schemas.
- RSpec layer: `type: :action`, surface callers, matchers, shared examples and the
  registry lint.
- `rails g action`, with the spec through `hook_for :test_framework`.
