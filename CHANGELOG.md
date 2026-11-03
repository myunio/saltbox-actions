# Changelog

## 0.1.0 (unreleased)

### Fixes from the 1.0 review

**Breaking.** Each changes what an app may already rely on:

- A list action with no model must call `authorize` (or `skip_authorization`), as every other
  action does. Its role was never asked before `perform`, so any caller with the read scope
  could run it. A list action on a model still needs only `policy_scope`.
- A `belongs_to` with `foreign_key:` is taken under its association's name and looked up
  through the person's scope: `belongs_to :account, foreign_key: :organization_id` takes
  `account`, no longer `organization_id` as a plain value. A foreign key that no one scope can
  check (polymorphic, part of a composite key, or shared by two associations) fails
  `rails actions:check`.
- A callable `default:` is filled in before the schema check and checked as if sent, as a
  literal one is: a callable returning `"lots"` for an integer is refused, no longer cast to 0.
  `invocation.arguments`, which the `confirm` hook sees, holds every default.
- The boot refuses an action name over 64 characters, with characters other than letters,
  digits, `_` and `-`, or that is one of the gem's own tools (`find_action`, `run_read_action`,
  `run_change_action`, `run_destructive_action`).
- A time of day is `00:00` to `23:59`: `24:00` and `99:99` are refused.
- With `strict_action_paths` off, an action other actions inherit from is an action, as in
  strict folders. Only `application_action.rb` files and `application_action/` folders hold
  base classes and shared code.

**Fixed:**

- ActionPolicy gets the context from `authorization_context_for` in every check, inside
  `perform` too, so a policy that declares `authorize :tenant` works once the action runs.
- With `result_format = :envelope`, a body of `null` is sent as `{"data": null}`, not `{}`.

### Names and defaults before 1.0

These names are the ones 1.0 keeps. Each rename is breaking and has no alias: an app on an
earlier commit renames its calls with the list below.

**`enforce_confirm` is on by default.** An agent's call to a `:confirm` action is refused with
`confirmation_required` until the app's `config.confirm` hook returns `true`. Every surface but
the person's own screen and the app itself counts as an agent, so a script on the API is refused
too, as are MCP and a browser assistant. With no `confirm` hook, every such call is refused. The
chat assistant still never runs a `:confirm` action, and a person on a screen and
`Caller.system` are never asked.

- To approve through the app, set the hook:
  `config.confirm { |invocation, action| Approval.granted?(invocation.caller.user, action.action_name, invocation.arguments) }`.
- To let agents run `:confirm` actions with nothing checked, on purpose:
  `config.enforce_confirm = false`. Agents are then only told to ask first.

**The default verbs are `list`, `show`, `export`, `create`, `update` and `delete`.** `cancel`,
`reinstate` and `publish` are no longer built in. An app that uses them declares them once in its
base class, which keeps them exactly as they were (on one record, not safe to repeat, agents
allowed, asking `cancel?`, `reinstate?` and `publish?`):

```ruby
define_verb :cancel, :reinstate, :publish, kind: :change, on: :member
```

**New:** `Error::InUse`, the class for the `in_use` code (a delete that other records still
depend on, from Active Record's `DeleteRestrictionError`); `Caller.webmcp(user)`; the Minitest
`tests Events::UpdateAction` macro, beside `self.action_class =`, which still works. Names
that are not part of the public API are marked `@api private`.

**Renamed** (old → new):

- Who calls:
  - Caller member `account`, keyword `account:` → `user`, `user:`; `Caller.system(account)` →
    `Caller.system(user)`; `SystemAccount` → `SystemUser`
  - the person, inside an action: `account` → `current_user` (a `User` member action keeps
    `user` for its record)
  - the caller, inside an action: `actor` → `current_caller`; `Base.new(actor:, params:)` →
    `Base.new(current_caller:, params:)`
  - the JSON API controller's hook: `resolve_caller` → `current_caller`
  - Caller member `agent`, keyword `agent:` → `agent_name`, `agent_name:`
    (`Caller.assistant(user, agent_name:)`, `Caller.system(agent_name:)`)
  - `Caller#allows?(scope)` → `Caller#includes_scope?(scope)` (`access.allows?(action)` stays)
  - `Caller#refresh!` → `Caller#refresh`
  - `Caller.screen(user, webmcp: true)` → `Caller.webmcp(user)`
  - adapter hooks: `permitted?(account)` → `permitted?(user)`,
    `permitted_attribute_names_for(principal, record)` → `permitted_attribute_names_for(user, record)`,
    ActionPolicy's `authorization_context_for(account)` → `authorization_context_for(user)`
- Declarations:
  - `connections :allowed / :confirm / :never` → `agents :allowed / :confirm / :never`;
    `define_verb connections:` → `define_verb agents:`
  - `returns(schema)` → `output_schema(schema)`, which also reads it back
  - `policy_query` (reader) → `policy_rule` with no argument; `VERB_QUERIES` → `VERB_RULES`
  - `paginated(per_page:, max_per_page:)` → `paginated(page_size:, max_page_size:)`
  - `Action.scope` (the token scope it needs) → `required_scope`
  - `available_to?(caller)` → `listed_for?(caller)`
- Configuration:
  - `after_change` → `after_change_commit`
  - `around_run` → `around_perform`
  - `schema_principal` → `schema_user`
  - `every_file_an_action` → `strict_action_paths`
  - `catalogue_path` → `catalog_path`
- Errors:
  - `Error::Invalid` → `Error::ValidationFailed` (the code stays `validation_failed`, and
    `validation_error` in the `:type` format)
  - `Error.from(result)` → `Error::ValidationFailed.from_result(result)`
  - `Invalid.for(errors, fallback:)` → `ValidationFailed.for(errors, fallback:)`
  - `Forbidden.fields(fields)` → `Forbidden.for_fields(fields)`
- Running: `Invocation.call(name:, caller:, arguments:)` → `Invocation.call(action:, caller:, arguments:)`
  (a name or an action class)
- Wire names:
  - catalog keys `connections` → `agents`, `scope` → `required_scope`
  - `find_action` match `arguments` (its JSON Schema) → `input_schema`;
    `response_description` → `output_description` (the run tools' `arguments` stay)
  - `GET /api/v1/actions` meta `count` → `total`, `version` → `catalog_version`
- Testing:
  - `run(arguments, as:, action:)` → `run_action(arguments, as:, action:)`, in RSpec and Minitest
  - `be_runnable_by` → `be_runnable_for`; `assert_runnable_by` → `assert_runnable_for`
  - `assert_matches_catalogue` → `assert_matches_catalog`
  - shared-example lets `permitted_account`, `unpermitted_account` → `permitted_user`,
    `unpermitted_user`
- Tasks and generators:
  - `rails actions:catalogue` → `rails actions:dump`
  - `rails g action ... --catalogue / --no-catalogue` → `--catalog / --no-catalog`
  - `rails g action ... --id / --no-id` → `--member / --no-member`
- "catalogue" is spelled "catalog" everywhere, including the `Catalog` module.
- Internal, now `@api private`, for a port whose own checks or tasks called them:
  `policy_query!` → `policy_rule!`, `declared_connections` → `declared_agents`,
  `declared_query` → `declared_rule`, `Registry.connection_problems` →
  `Registry.agents_problems`, `InvocationJob::SystemAccountSerializer` →
  `InvocationJob::SystemUserSerializer`. A `perform_later` job queued with `Caller.system`
  before the upgrade carries the old serializer's name and cannot be run after it: let the
  queue drain first.

### Earlier in 0.1.0

- An action in a module its model is not in asks that module's policy, as Pundit's
  `authorize [:admin, record]` does: `Admin::Projects::ListAction` asks `Admin::ProjectPolicy`,
  never `ProjectPolicy`, in `permitted?`, the record loader, `authorize`, `policy_scope`, its
  fields and the records a reference may pick. A missing namespaced policy fails closed
  (Pundit's `NotDefinedError`, ActionPolicy's `NotFound`) and `rails actions:check` names it,
  as it names a reference field whose namespaced scope is missing.
- An action whose policy is missing, namespaced or not, is left out of every actions list (the
  JSON API's, MCP's `tools/list` and `find_action`, the assistant's tools), so the other actions
  stay listed. Before, one missing policy made every list raise for every caller. Running the
  action still fails, `rails actions:check` names the policy, and the first list warns once per
  action, through the Rails logger once Rails has one.
  ActionPolicy lookups in a namespace no longer fall back to the model's own policy, and skip a
  `policy_class` the model or record defines; Pundit's `policy` helper asks the namespace too.
  `policy_namespace :staff` declares another namespace, `policy_namespace false` the model's own
  policy; it replaces the ActionPolicy adapter's overridable `policy_namespace` method, and a
  value that names no module, such as `""`, `true`, `1` or `[]`, raises `ArgumentError`. A declaration holds for
  subclasses in its modules and below them; a subclass adds the modules its name has beyond the
  declaring class's, so `policy_namespace :staff` in a base class makes
  `Admin::Projects::ListAction` ask `Staff::Admin::ProjectPolicy`, the same in
  `Admin::ApplicationAction` makes it ask `Staff::ProjectPolicy`, and an `Admin::` subclass of an
  action that declares `false` still asks `Admin::ProjectPolicy`.
- Every module around the action counts, except the one that names its model and the model's own
  modules. So these are renamed and ask a namespaced policy, failing closed until it exists or
  the action declares `policy_namespace false`:
  - a single module: `Admin::ExportAction` on `Project` is `export_admin_projects` and asks
    `Admin::ProjectPolicy`; `Reports::ExportAction` on `Customer` is `export_reports_customers`
    and asks `Reports::CustomerPolicy`;
  - a nested resource: `Events::Attendees::ListAction` on `Attendee` is `list_events_attendees`
    and asks `Events::AttendeePolicy`;
  - an area module: `Crm::Organizations::ListAction` on a top-level `Organization` is
    `list_crm_organizations` and asks `Crm::OrganizationPolicy` (on `Crm::Organization` nothing
    changes).

  `rails actions:check` names each missing policy, and says when the outer module names a model
  (`Events` names `Event`), so the action may be nested: declare `policy_namespace false` only if
  everyone the model's own policy allows may run it.
- An action with no model counts every module it is in, as it has no model's modules to leave
  out. `Admin::CountProjectsAction`, with a declared name, asked `ProjectPolicy` in its own
  `authorize Project` and `policy_scope(Project)`; it asks `Admin::ProjectPolicy`, failing closed
  until it exists. A module named like a model counts too: `Events::TallyAction` with no model
  asks `Events::EventPolicy`. Declare `policy_namespace false` to ask the models' own policies.
  An action with no model at the top level is unchanged. `rails actions:check` cannot name the
  policy, since only `perform` says which model it authorizes; the error names it. With
  ActionPolicy, `policy_scope` in a namespace without the policy raises
  "Couldn't find Admin::ProjectPolicy for Project", instead of falling back to the action as its
  authorization target.
- `Admin::Billing::Invoices::ListAction` finds `Billing::Invoice`: a model lookup drops outer
  modules from the left before trying the top-level model. Such an action was named `list` with no
  policy check; it is `list_admin_billing_invoices` and asks `Admin::Billing::InvoicePolicy`.
- An isolated engine's action on a host model keeps one namespace in its name:
  `Billing::Projects::ListAction` in a folder named `billing` is `list_billing_projects`, and asks
  `Billing::ProjectPolicy`.
- That module is part of the action's name: `Admin::Projects::ListAction` is `list_admin_projects`,
  with the CLI command `admin-projects list` and the title "List admin projects", so it no longer
  collides with `Projects::ListAction`, and a summarized admin list points agents at
  `show_admin_project`. `Naming#outer_namespace` gives it. Names of actions inside their model's
  namespace do not change.
- Errors by field hold each message without the field's name (`{"title" => ["can't be blank"]}`),
  as a record's `errors.as_json` does, so a screen that adds them back shows them once.
- A fresh development or test process draws its routes before the first render, so its first
  links use the routes' `default_url_options` instead of `example.org`.
- A list with a summary may `render json:` beside `collection:`: screens get the json (an Alba or
  Blueprinter resource), agents the summaries of the collection.
- A field the input does not list is refused as "update_note does not take user_id. It takes id,
  title, body." A request body sent without `Content-Type: application/json` says so.
- A named action with a model and no `policy_rule` raises the message `rails actions:check`
  gives, instead of a `TypeError`.
- With no authorization adapter, the generator leaves `belongs_to` fields out of `accepts`,
  commented, and says why. It says the generated test has placeholders to fill in.
- `announce_changes` and `assert_announces_changes` say how to install change tracking when
  nothing notes changes.

- `Caller.system` runs an action as the app itself, from a job, a rake task or the console. It is
  not an agent: `agents` never bar it, it holds every scope and is never asked to confirm.
  Its user is `Saltbox::Actions::SystemUser` unless the app passes one, and the policy sees
  it like a person, so the app decides what it may do. `Caller#system?` tells it apart. The JSON
  API controller, MCP and the assistant raise `ArgumentError` for a system caller. `perform_later`
  carries it to the job. The test helpers add `as_system`.
- Actions are Active Model objects, named like controllers. `Events::UpdateAction` lives in
  `app/actions/events/update_action.rb`; its model is the namespace, singular, as
  `wrap_parameters` finds it (`Admin::Events` tries `Admin::Event`, then `Event`), and
  `model Customer` overrides it. An action in its model's own namespace (`Event::UpdateAction`)
  stops the boot. Public names do not change: it is still `update_event`.
- Input is declared with Active Model: `attribute :reason, :string` for anything that is not a
  model field, and validations for its checks. The JSON Schema is derived from them: `presence`
  makes a field required, `inclusion` gives its enum, `length` and `numericality` its bounds.
  Validations with `if:`, `unless:` or `on:` run but stay out of the schema. Validations run on
  every call after the schema check and before `confirm`, and a failure is `validation_failed`
  by field. Each attribute is cast once by its Active Model type and read as a method.
  `argument` and its keyword options are removed. An attribute named like a method every
  action has (`params`, `errors`, `authorize`) is refused.
- One list of model fields: a create or update takes the fields its policy permits (Pundit, or
  ActionPolicy with `permitted_attributes`). Without such a policy an action lists them with
  `accepts`; `accepts` beside a policy that supplies fields fails `rails actions:check`.
  Adapters answer `supplies_fields?`.
- The verb carries the defaults: kind, whether it works on one record, whether it is safe to
  repeat, and its rule for agents (`:confirm` for a destructive action, `:allowed` for the
  rest). `agents` is declared only where an action departs from its verb, and
  `Configuration#default_connections` is removed. `update` and `delete` are now idempotent.
  `define_verb :archive, kind: :change, on: :member, idempotent: true` adds an app's own verbs
  in its base class; `verbs` reads the table. `idempotent false` overrides a verb.
- A member action loads its record before `perform`, as CanCanCan's
  `load_and_authorize_resource` does: through `policy_scope`, by `id` (or the action's
  `find_<record>(scope)`), then `authorize`. It sets `@event` for the view and the reader `event`
  returns it. `rails actions:check` refuses an attribute named like the reader.
  `attribute :id` declares a member action for a verb outside the table.
- `paginated(page_size: 25, max_page_size: 100)` declares `page` and `page_size` as attributes.
- `featured` replaces `mcp_core`, in the class and on the wire: the catalog's `mcp_core` key is
  now `featured`. A client that reads the catalog reads the new key.
- `policy_rule :archive?` replaces the class-level `authorize :archive?`.
- Titles and descriptions are written in the class. A locale entry wins over the class text,
  as Action Mailer's `default_i18n_subject` does. A field's description comes from the action's
  locale entry, then the resource's (`actions.events.fields`), then the attribute's
  `description:`, then `actions.shared.fields`. The generator no longer writes a locale entry.
- `Events::UpdateAction.perform_now(caller:, **input)` runs an action through every check;
  `perform_later` runs it through Active Job (`Saltbox::Actions::InvocationJob`), checking
  everything again when the job runs and dropping it on a refusal.
- `Error::ValidationFailed.for(errors)` turns Active Model errors into a `validation_failed` refusal.
- A subclass of an action inherits its `agents`, `policy_rule`, `permission`, `feature`,
  `featured`, `idempotent`, `attribute :id` and `accepts`, as `class_attribute` does. Before, a
  subclass lost them, so a parent's `agents :never` or `permission` did not reach it.
- `rails actions:check` refuses a model whose record reader would replace a method every action
  has (`current_user`, `result`), a string attribute whose `inclusion` lists symbols, and `presence`
  on a boolean. A `find_<record>` that returns `nil` is `not_found`.
- A `:datetime` attribute reads a local date and time in the app's `Time.zone`, as a datetime
  column does, in a list too. `cli args: [:id]` works for an action that takes an id. An
  attribute with a lambda default is not required in the schema. `rails actions:check` refuses
  a validation of a name that is not an attribute, such as a model field.

- Booting never touches the database. With eager loading, the boot checks only what each action
  declares (name, verb, kind, agents rule, unique names and CLI commands). `rails actions:check`
  runs every other check (policy rules, fields, summaries, `check_action` and `check_registry`), as
  do the registry shared example and `assert_valid_action_registry`. It and `actions:dump`
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
- `schema_user` is used only where there is no caller: the committed catalog,
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
  nothing on a problem, and puts back every file it wrote when the catalog step fails; either
  failure exits 1. A new action declares no `agents` rule and leaves it to its verb. The spec
  template assumes no factories or roles and passes the id for any verb that takes one.
- The shared example "refuses callers the action does not allow" checks a person without
  rights only when the spec defines `unpermitted_user`.
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
  `confirmation_required` unless the app's `config.confirm` hook approves it. On by default
  (see "Names and defaults before 1.0").
- `Caller#confirm!(action)` applies another action's `agents` rule inside a running action.

- `summary` declares the fields a list action sends agents in place of its view, once per model
  in the base class or on one action. It replaces `cli_columns` and the `columns:` of `cli`:
  the catalog's `cli.columns` is now the top-level `summary`. A list's catalog `output_schema`
  is its `summary_output_schema`. `render collection:` hands over a list's records; a list with a
  summary refuses `render json:`, missing records, field values whose JSON is not plain, and
  meta that is not plain data (hashes, arrays, text, numbers, booleans, dates, times, nil).
- find_action finds an action only through its title or name, or two or more of the
  request's words in its description; one shared description word no longer matches.

- Each call gets its own deep copy of an argument's default.
- The API encodes the body once, so a string body arrives as a JSON string.

- MCP and RubyLLM send `false` and `null` bodies as JSON; only `head` reads "Done." (`FrontDoor::EMPTY`).
- Argument defaults are checked against the schema and satisfy a required input.
- `Invocation#invocation_id` stays readable in a deferred `after_change_commit`.

- A change runs in its own savepoint, so a failure rolls back inside a caller's transaction.
- `after_change_commit` runs once every enclosing transaction commits, and never on rollback.
- `render json: false` and `render json: nil` send that JSON; `Result#empty?` marks `head`.
- A declared `permission` replaces the policy's role question (`permitted?`) rather than adding to it.
- Argument defaults are filled in at run time.
- The registry shared example works with `strict_action_paths` off.

- For apps whose names were public first: `action_name`, `title`, `description` and `cli`
  declarations, `argument` descriptions and JSON Schema keywords.
- A `permission` gate (`any_of`, `:everyone`) with `config.permissions_held`, and
  `enforce_permissions` to let it decide only the actions list.
- `error_format :type` and `result_format :envelope`, `render meta:`, `Result#meta`.
- `strict_action_paths`, `validate_arguments`; app error
  mappings are checked before the gem's own.

- Extracted from an internal application's action layer.
- Core: naming, declarations, input schema from policy-permitted columns, argument
  checks, the catalog, rendering, permitting, invocation, registry boot checks,
  the front door (find_action and run tools) and the finder.
- Authorization adapters for Pundit and ActionPolicy.
- Surface adapters: MCP (streamable HTTP), RubyLLM tools, and a controller concern
  for /api/v1/actions.
- Hooks for the app's tenancy, audit, change publishing, feature flags, areas,
  error mapping and per-connection access.
- `output_schema` declarations.
- RSpec layer: `type: :action`, surface callers, matchers, shared examples and the
  registry lint.
- `rails g action`, with the spec through `hook_for :test_framework`.
