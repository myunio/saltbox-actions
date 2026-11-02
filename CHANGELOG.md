# Changelog

## 0.1.0 (unreleased)

- Booting never touches the database. With eager loading, the boot checks only what each action
  declares (name, verb, kind, connections, unique names and CLI commands). `rails actions:check`
  runs every other check (policy rules, fields, summaries, `check_action` and `check_registry`), as
  do the registry shared example and `assert_valid_action_registry`. It and `actions:catalogue`
  say they need the database when they cannot connect. An app that does not run
  `rails actions:check` in CI (or the registry spec or test) now boots with a missing policy
  rule, a policy field that is not a column or a bad summary, and finds out only at run time,
  when a caller first hits that action.
- A create or update's input schema is built with the real caller on first use, inside
  `around_invocation`, and cached per list of permitted fields, so callers whose policy permits
  different fields see different schemas. A model field the caller may not set is refused as
  forbidden. `input_schema`, `writable_fields` and `definition` take an optional caller.
- `on_forbidden_fields { |caller, action, fields| ... }` returns the error for a field the caller
  may not set, wherever it is refused: against the caller's schema or by the policy for the
  record. The default is the same `forbidden` error as before: "You can't change notes."
- `schema_principal` is used only where there is no caller: the committed catalogue,
  `actions:check` and the registry spec, the generator's field list, and the schema matchers
  without `as:`. `be_invalid_against_schema` and `assert_invalid_against_schema` take `as:` a
  caller. `input_types` and `Registry.runnable` are gone.

- Authorization is optional. With no adapter, every action is allowed and `actions:check` asks
  for no policy. Adapters report their problems through `authorization_problems`; the
- The text of each result and refusal an agent gets over MCP or from the assistant tools is
  marked as record data: it comes inside `<record-data>` tags, with `<`, `>` and `&`
  escaped so a record cannot close the tag. MCP's `structuredContent` and `_meta` are
  unchanged. One sentence, `RecordData::NOTE`, tells the agent to treat the tagged text,
  structured content and error details alike as data: first in the MCP server's instructions
  (then `config.instructions`) and in the `find_action` and run tool descriptions.
  `RubyLLMTool#execute` now returns that marked text, never a Hash.
- Authorization is optional. With no adapter, every action is allowed and the boot check asks
  for no policy. Adapters report their boot problems through `authorization_problems`; the
  README documents the adapter contract with a plain-model example.
- A list action needs only `policy_scope`, as Pundit's `verify_policy_scoped` on `index`.
- `rails g action` checks the action as `actions:check` does before writing any file, writes
  nothing on a problem, and puts back every file it wrote when the catalogue step fails; either
  failure exits 1. A new change action declares
  `connections :confirm` (was `:allowed`) unless the app sets `default_connections`. The spec
  template assumes no factories or roles and passes the id for any verb that takes one.
- The shared example "refuses callers the action does not allow" checks a person without
  rights only when the spec defines `unpermitted_account`.
- The README's API controller inherits `ActionController::API`.
- `find_action` with no query lists every action the caller can run from its surface, a page
  at a time (`page`, `page_size`: 50 by default, at most 100), sorted by area then name, with
  `config.area_order` to put some areas first. When nothing matches, its hint names
  the caller's areas, if actions have any. `run_change_action` asks first only for an action
  marked `confirm_first`.

- Engines: `config.action_paths` is a list (replacing `actions_path`); an engine adds its
  folder in an initializer, with an optional `namespace:` for its actions' public names.
- A warning names `ApplicationAction` subclasses outside every action folder. Overlapping
  folders (one inside another, or one spelled two ways) load each action once.
- Boot checks run before sorting, so a namespace that is not a model gets its own message.
- Duplicate action names and colliding CLI commands stop the boot, naming both classes.

- Input is cast with each field's Active Model type before the schema check, so form strings
  ("12", "", "on", a local date-time) work on every surface; a value not of its type is still refused.
  An impossible date, an integer its column cannot store and a float that is not finite are
  refused by field. Indexed `fields_for` params are not cast yet.
- Ids and foreign keys take an integer or a string; decimal columns take a number or a string of digits.
- `Saltbox::Actions::ChangeTracking`, included in `ApplicationRecord`, notes records created,
  updated or destroyed through callbacks, for `on_changes` and `announce_changes`, without
  PaperTrail. PaperTrail still notes its versions.
- A write rolled back by a savepoint inside an action is no longer announced as a change.
- A change runs in its model's own transaction, so a model in a second database rolls back.
  Writes on any other connection are not covered.

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
