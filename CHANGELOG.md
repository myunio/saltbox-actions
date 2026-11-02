# Changelog

## 0.1.0 (unreleased)

- Authorization is optional. With no adapter, every action is allowed and the boot check asks
  for no policy. Adapters report their boot problems through `authorization_problems`; the
  README documents the adapter contract with a plain-model example.
- A list action needs only `policy_scope`, as Pundit's `verify_policy_scoped` on `index`.
- `rails g action` checks the action against the boot check before writing any file, writes
  nothing on a problem, and stops after a failed catalogue step. A new change action declares
  `connections :confirm` (was `:allowed`) unless the app sets `default_connections`. The spec
  template assumes no factories or roles and passes the id for any verb that takes one.
- The shared example "refuses callers the action does not allow" checks a person without
  rights only when the spec defines `unpermitted_account`.
- The README's API controller inherits `ActionController::API`.
- Input is cast with each field's Active Model type before the schema check, so form strings
  ("12", "", "on", a local date-time) work on every surface; a value not of its type is still refused.
  An impossible date, an integer its column cannot store and a float that is not finite are
  refused by field. Indexed `fields_for` params are not cast yet.
- Ids and foreign keys take an integer or a string; decimal columns take a number or a string of digits.

- `enforce_confirm`: when on, an agent's call to a `:confirm` action is refused with
  `confirmation_required` unless the app's `config.confirm` hook approves it. Off by
  default, which keeps `:confirm` as advice to agents.
- `Caller#confirm!(action)` applies another action's `connections` rule inside a running action.

- `summary` declares the fields a list action sends agents in place of its view, once per model
  in the base class or on one action. It replaces `cli_columns` and the `columns:` of `cli`:
  the catalogue's `cli.columns` is now the top-level `summary`. A list's catalogue `output_schema`
  is its `summary_output_schema`. `render collection:` hands over a list's records; a list with a
  summary refuses `render json:`, missing records, field values whose JSON is not plain, and
  meta that is not plain data (hashes, arrays, text, numbers, booleans, dates, times, nil).
- find_action finds an action only through its title or name, or two or more of the
  request's words in its description; one shared description word no longer matches.

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
