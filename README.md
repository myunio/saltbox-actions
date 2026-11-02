# saltbox-actions

**saltbox-actions lets you write each thing a person can do in your Rails app
once, as one class, and serve it to your screens, a JSON API, AI agents over
MCP and an in-app chat assistant.**

## Why

A Rails app used to have one way in: its screens. Now people also reach it
through scripts, AI agents and chat assistants. Each new way in tends to grow
its own copy of the same rules: who may do this, which fields they may change,
what the input looks like, and what comes back. Over time the copies drift
apart, and an agent can do something the screen would refuse.

saltbox-actions puts each rule in one place. An **action** is a small class,
written like a controller action. Every way in runs the same class, through
the same checks, and gets the same errors.

## A quick look

Here is an action that renames an event in a made-up events app:

```ruby
# app/actions/event/update_action.rb
class Event::UpdateAction < ApplicationAction
  connections :allowed   # agents and scripts may run it
  idempotent

  def perform
    @event = policy_scope(Event).find(params[:id])
    authorize @event
    @event.update!(permitted_attributes(@event))
    render :show         # app/views/events/show.json.jbuilder
  end
end
```

The class name gives most of the settings. `Event::UpdateAction` works on
`Event`, asks the policy's `update?` rule, and is named `update_event`. Its
input is an `id` plus the fields your policy permits, typed from the model's
columns.

Call it from a controller:

```ruby
class EventsController < ApplicationController
  def update
    result = ApplicationAction::Invocation.call(
      name: "update_event",
      caller: ApplicationAction::Caller.screen(current_user),
      arguments: params.permit(:id, :title, :starts_on).to_h
    )
    render json: result.as_json, status: result.status
  rescue Saltbox::Actions::Error => error
    render json: error.as_json, status: error.status
  end
end
```

Serve it to AI agents over MCP, from a Rack endpoint you mount at `/mcp`:

```ruby
class McpEndpoint
  def call(env)
    token = ApiToken.find_by_bearer(env["HTTP_AUTHORIZATION"])  # your own credential check
    return [401, {}, []] unless token

    caller = ApplicationAction::Caller.new(account: token.user, surface: "mcp",
      agent: token.client_name, scopes: token.scopes)
    Saltbox::Actions::MCP.call(env, caller:, name: "events", allowed_hosts: ["events.example.com"])
  end
end
```

And test it, as an agent would call it:

```ruby
# spec/actions/event/update_action_spec.rb
RSpec.describe Event::UpdateAction do
  let(:manager) { create(:user, :manager) }
  let(:event) { create(:event, title: "AGM") }

  it "renames the event" do
    result = run({id: event.id.to_s, title: "Annual meeting"}, as: as_mcp(manager))
    expect(result.body.dig("data", "event", "title")).to eq("Annual meeting")
  end
end
```

When the app boots in production or CI, it checks every action. If an action
leaves out a setting it needs, the boot stops and the error names the fix.

## Install

saltbox-actions needs Ruby 3.4 or later and Rails 8.0 or later. It is not on
RubyGems yet, so install it from GitHub and pin a commit:

```ruby
# Gemfile
gem "saltbox-actions", github: "myunio/saltbox-actions", ref: "<commit sha>"
gem "jbuilder"   # action views
gem "pundit"     # or gem "action_policy"
```

Add these too, but only for the parts you use:

| Gem | Needed for |
|---|---|
| `mcp` | Serving actions to AI agents over MCP |
| `ruby_llm` | Tools for an in-app chat assistant |
| `paper_trail` | The audit trail helper and the `change_audit_trail` matcher |

Then make a base class for your actions and pick your authorization library:

```ruby
# app/actions/application_action.rb
class ApplicationAction < Saltbox::Actions::Base
  include Saltbox::Actions::Authorization::Pundit   # or ::ActionPolicy
end
```

## Core concepts

### Actions

An action lives in `app/actions/`, one per file, named
`<model>/<words>_action.rb`. Its `perform` method works like a controller
action. It loads records through `policy_scope`, calls `authorize`, does the
work, then calls `render` or `head`. If `perform` skips `authorize` or
`policy_scope`, the action fails, just as Pundit's `verify_authorized` would.

`render :show` draws a Jbuilder view from the model's view folder, such as
`app/views/events/show.json.jbuilder`. Instance variables you set in
`perform` reach the view, as they do from a controller. You can also send a
body with no view: `render json: {count: 3}`.

### Names come from the class

The first word after the model is the **verb**. These verbs are built in:

| Verb | Kind | Takes an `id` | Policy rule |
|---|---|---|---|
| `list` | read | no | `index?` |
| `show` | read | yes | `show?` |
| `export` | read | no | `export?` |
| `create` | change | no | `create?` |
| `update` | change | yes | `update?` |
| `cancel` | change | yes | `cancel?` |
| `reinstate` | change | yes | `reinstate?` |
| `publish` | change | yes | `publish?` |
| `delete` | destructive | yes | `destroy?` |

So `Event::ListAction` is named `list_events`, and `Event::ShowNotesAction`
is named `show_event_notes`. Rails spellings such as `DestroyAction` or
`IndexAction` stop the boot, because the names are public: agents and
scripts call them.

The **kind** decides what a token needs. A read needs the `api:read` scope.
A change or a destructive action needs `api:write`.

A verb outside the table, or a name with more than a verb, declares what it
needs:

```ruby
class Event::ArchiveAction < ApplicationAction
  kind :change
  argument :id
  authorize :archive?
  connections :confirm

  def perform
    @event = policy_scope(Event).find(params[:id])
    authorize @event
    @event.update!(status: "archived")
    render :show
  end
end
```

### Callers

A **caller** says who runs an action and from where. It holds the person
(`account`), the **surface** they come from, the agent's name, and the token's
scopes. The surfaces are:

- `screen`: a person on your app's own screens;
- `webmcp`: a browser assistant on the person's page;
- `api`: a script with a token;
- `mcp`: an AI agent;
- `assistant`: your app's own chat.

Build a caller from a real credential, never from anything the client sends:

```ruby
ApplicationAction::Caller.screen(current_user)
ApplicationAction::Caller.assistant(current_user)
ApplicationAction::Caller.new(account: token.user, surface: "api", agent: "Billing script", scopes: token.scopes)
```

### Connections

Every action declares `connections`. It says whether anything other than the
person's own click may run it:

- `:allowed`: agents, scripts and assistants may run it.
- `:confirm`: agents are told to ask the person first. The chat assistant
  never runs it.
- `:never`: only the person, on a screen.

A browser assistant (`webmcp`) never runs a destructive action.

By default, nothing on the server checks that an agent asked before a
`:confirm` action. The agent is only told to. To make the server check, turn
on `enforce_confirm` and say how a person approves:

```ruby
Saltbox::Actions.configure do |config|
  config.enforce_confirm = true
  config.confirm do |invocation, action|
    Approval.granted?(invocation.caller.account, action.action_name, invocation.arguments)
  end
end
```

With it on, an agent on the API, MCP or a browser page gets
`confirmation_required` for a `:confirm` action, until the hook returns
`true`. The hook sees the caller, the action and the checked arguments, so it
can ask the person in your app. It can also raise an error of its own, such as
`Saltbox::Actions::Error::ConfirmationRequired.new("Approve it under Requests in the app")`.
A person on a screen is never asked. Without a hook, every such call is
refused.

Some actions can reach what a stricter action guards: a create that can also
publish, say. Check the stricter rule inside `perform`:

```ruby
actor.confirm!(Event::PublishAction) if params[:status] == "published"
```

`confirm!` refuses with `human_required` when that action's `connections`
bar the caller, and with `confirmation_required` when it is `:confirm` and
not approved. Call it before the action writes anything: a refusal rolls
back the change, including anything the hook wrote.

### The order of refusals

Every surface runs an action through `Saltbox::Actions::Invocation`. It
refuses in the same order every time, so the same call gets the same answer:

1. The action's feature flag is off: `not_found`.
2. Its `connections` rule bars this caller: `human_required`.
3. The caller's access does not reach the action.
4. The token lacks the scope: `insufficient_scope`.
5. The person's role or permissions do not allow it: `forbidden`.

Then the input is checked against the action's JSON Schema. A bad field gives
`validation_failed`, with errors by field name. A record the person cannot
see gives `not_found`, so its existence never shows. With `enforce_confirm`
on, a `:confirm` action the app has not approved gives
`confirmation_required` before it runs.

A change runs in its own database transaction. If it fails, its writes are
undone.

Every surface sends errors in the same shape:

```json
{"error": {"code": "forbidden", "message": "You don't have permission to do this."}}
```

To refuse in your own words, raise an error from `perform`:

```ruby
raise ApplicationAction::Error.new("Published events are locked", code: :event_locked, status: :unprocessable_content)
```

### Limit what a connection reaches

A token's scopes are broad: read, or read and write, across every action. To
let one connection reach only some actions, give its caller an `access:`
object that answers `allows?(action)`:

```ruby
# app/models/connection_access.rb
ConnectionAccess = Data.define(:action_names) do
  def allows?(action) = action_names.include?(action.action_name)
end
```

Build the caller with it wherever you build one from a token. Here
`token.action_names` stands for your own record of what the person allowed:

```ruby
ApplicationAction::Caller.new(account: token.user, surface: "mcp", agent: "Claude",
  scopes: token.scopes, access: ConnectionAccess.new(token.action_names))
```

The caller then sees only those actions. The catalogue, `find_action` and the
MCP tools leave the rest out, and a call to one of them is refused with
`insufficient_scope`. The default message talks about read-only tokens, so
set `on_access_refused` to say what happened in your words. It is also the
place to note the refusal:

```ruby
# config/initializers/actions.rb
Saltbox::Actions.configure do |config|
  config.on_access_refused do |caller, action|
    Saltbox::Actions::Error::InsufficientScope.new("This connection may not use #{action.title}. Allow it in Settings.")
  end
end
```

### Declarations

Put these at the top of an action class when the name cannot give them.

| Declaration | What it does |
|---|---|
| `connections :allowed` | Required. Who besides the person may run it (see above). |
| `kind :read` | The kind, for a verb outside the table. `:read`, `:change` or `:destructive`. |
| `authorize :archive?` | The policy rule, when it is not the verb's own. |
| `argument :reason, :string` | An input that is not a field the policy permits. |
| `idempotent` | Running it twice with the same input changes nothing more. |
| `mcp_core` | Lists it as an MCP tool of its own (see below). |
| `feature "key"` | A feature flag. While it is off, callers get `not_found`. |
| `permission "events.manage"` | Permission keys the person must hold. `any_of("a", "b")` takes one of several. `permission :everyone` lets every signed-in person in. |
| `returns(schema)` | The JSON Schema of the body it renders. |
| `title "..."`, `description "..."` | Text for agents. By default these come from `config/locales/actions.en.yml`. |
| `action_name "count_events"` | A name of your own, in place of the one from the class. The action then declares its `kind` too. |
| `summary :id, :title` | The fields a list sends agents, and the columns a command-line client prints (see below). |
| `cli "events count"` | The command for a command-line client you build on the catalogue. |

`argument` takes a type: `:string`, `:integer`, `:decimal`, `:boolean`,
`:date`, `:time`, `:array` or `:hash`. It also takes `required:`,
`nullable:`, `enum:`, `of:` (what an array holds), `description:`, and the
JSON Schema keywords `format`, `minimum`, `maximum`, `min_length`,
`max_length`, `pattern` and `default`:

```ruby
argument :page, :integer, minimum: 1, default: 1, description: "Page number, from 1"
argument :payments, :array, of: {amount: :decimal, paid_on: :date}
```

### Lists for agents

A list's view often sends every field of every record. A person's screen
needs that; an agent reading a list does not. Declare a model's **summary**
once, in your base class, and every list of that model sends agents each
record's summary instead:

```ruby
# app/actions/application_action.rb
class ApplicationAction < Saltbox::Actions::Base
  include Saltbox::Actions::Authorization::Pundit

  summary Event, :id, :title, :starts_on, status: ->(event) { event.status.humanize }
end
```

Name the record's own attributes or methods, and compute any other field
with a lambda that takes the record. Keep `id` in it, so the agent can pick
a record and run the show action for the rest. Leave links out, such as
signed file URLs: an agent's transcript keeps everything it reads.

Each field holds one plain value: text, a number, true or false, a date or
time, or nil. Decimals and dates are sent as text. A record, a hash or a list
stops the call with an error, so no field the summary leaves out reaches an
agent inside another. The `meta:` beside it is your own plain data, such as
paging: hashes, arrays, text, numbers, true or false, dates, times and nil.
Anything else in it, such as a record or a set of them, stops the call too.

`Event::ListAction` needs no change. It sets `@events` and calls
`render :index, meta: {page: 2}`. Screens get views. Every other caller (the
API, MCP, WebMCP and the assistant) gets summaries:

```json
{"data": {"events": [{"id": 7, "title": "AGM", "starts_on": "2026-07-01", "status": "Published"}]}, "meta": {"page": 2}}
```

A list action is one whose class name's verb is `list`. If it keeps its
records under another name, or declares its own `action_name`, hand them
over with `render :index, collection: @upcoming`. A list with a summary
always renders a template and always hands over its records: `render json:`,
or no records, stops the call with an error, rather than sending agents more
than the summary.

A model with no summary sends the view to everyone. An action can declare its
own `summary :id, :title` in place of its model's. The catalogue lists the
summary's fields as `summary`, which a command-line client prints as a table's
columns, on every action of the model. For a list, its `output_schema`
describes the summaries agents get, and `find_action` tells agents which
fields a list returns.

### Titles and descriptions

Agents choose tools by their descriptions, so write one for every action:

```yaml
# config/locales/actions.en.yml
en:
  actions:
    event/update:
      description: Changes an event's title, date or capacity.
      fields:
        title: The event's name.
```

## Adapters

Each adapter loads only when you first use it, so you add only the gems you
need.

### JSON API

Include `Saltbox::Actions::Controller` and say who is calling:

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    get "actions", to: "actions#index"
    get "actions/:name", to: "actions#show"
    post "actions/:name", to: "actions#run"
  end
end

# app/controllers/api/v1/actions_controller.rb
class Api::V1::ActionsController < ApplicationController
  include Saltbox::Actions::Controller

  private

  def resolve_caller
    token = ApiToken.find_by_bearer(request.authorization) || raise(Saltbox::Actions::Error::Unauthorized)
    ApplicationAction::Caller.new(account: token.user, surface: "api", agent: token.name, scopes: token.scopes)
  end
end
```

`GET /api/v1/actions` lists the actions this caller may run.
`POST /api/v1/actions/update_event` runs one, with a body of
`{"arguments": {"id": "42", "title": "AGM"}}`.

### MCP

`Saltbox::Actions::MCP.call` answers one MCP request over stateless HTTP,
using the `mcp` gem. Your app keeps its own credential check, as in the
example at the top.

Agents see a short list of tools, not one per action:

- each action declared `mcp_core`, as a tool of its own (keep these to about
  fifteen);
- `find_action`, to search all the others; with no query, it lists every
  action the person can reach;
- `run_read_action`, `run_change_action` and `run_destructive_action`, to run
  what `find_action` found.

`find_action` marks each action `confirm_first` when it is declared
`connections :confirm`. The change tool tells the agent to ask before those
and to go ahead with the rest, saying what it is changing. The remove tool
always asks first.

If your app sorts actions into areas (`config.area_for`), the list is sorted
by area, then name. Set `config.area_order = %w[events billing]` to put
those areas first.

### In-app assistant

`Saltbox::Actions::RubyLLMTool` turns the same tools into RubyLLM tools for a
chat:

```ruby
caller = ApplicationAction::Caller.assistant(current_user)
chat.with_tools(*Saltbox::Actions::RubyLLMTool.for(caller))
```

### Authorization

`Saltbox::Actions::Authorization::Pundit` asks your Pundit policies.
`Event::UpdateAction` asks `EventPolicy#update?`, and its input takes the
fields from the policy's `permitted_attributes`.

`Saltbox::Actions::Authorization::ActionPolicy` does the same with
ActionPolicy. ActionPolicy has no `permitted_attributes`, so define one on
the policy, returning field names, if create and update actions should take
the model's fields.

### PaperTrail

With PaperTrail, every version an action writes is noted as a change, and
each version can record the agent and surface:

```ruby
# config/initializers/actions.rb
Rails.application.config.after_initialize { Saltbox::Actions::PaperTrail.install! }

Saltbox::Actions.configure do |config|
  config.around_run do |invocation, run|
    Saltbox::Actions::PaperTrail.request(invocation, agent: invocation.caller.agent) { run.call }
  end
end
```

Each keyword after `invocation` goes to PaperTrail's `controller_info`, so a
richer agent stamp (the machine, the connection) goes there, with a column on
`versions` for each.

## Testing with RSpec

Load the helpers in `spec/rails_helper.rb`:

```ruby
require "saltbox/actions/rspec"
```

Specs under `spec/actions/` get `type: :action`, and `described_class` is the
action. `run(arguments, as: caller)` runs it the way every surface does.

**Callers:** `as_screen(user)`, `as_webmcp(user)`, `as_api(user, scopes:)`,
`as_mcp(user, scopes:)`, `as_assistant(user)` and `as_read_only(user)`. By
default each builds a plain caller. To build them from your own tokens, set
a factory for each surface:

```ruby
Saltbox::Actions::RSpec.configure do |config|
  config.caller_for(:mcp) do |user, scopes:|
    token = create(:api_token, user:, scopes:)
    ApplicationAction::Caller.new(account: user, surface: "mcp", agent: "Test agent", scopes: token.scopes)
  end
end
```

**Matchers:**

- `be_refused.with(:forbidden)` and `be_not_found`;
- `have_field_errors(:title)`;
- `be_invalid_against_schema`, for input the schema refuses;
- `match_output_schema`, against the schema from `returns`;
- `announce_changes(event => :update)`;
- `change_audit_trail.on(event).by(user).with(agent: "Test agent")` (needs PaperTrail);
- `be_runnable_by(caller)` and `be_listed_for(caller)`.

**Shared examples:**

```ruby
RSpec.describe Event::UpdateAction do
  let(:permitted_account) { create(:user, :manager) }
  let(:unpermitted_account) { create(:user) }
  let(:event) { create(:event) }
  let(:arguments) { {id: event.id.to_s, title: "AGM"} }

  it_behaves_like "refuses callers the action does not allow"
  it_behaves_like "hides records the caller cannot see" do
    let(:hidden_arguments) { {id: create(:event, :other_team).id.to_s} }
  end

  it "refuses a bad capacity" do
    expect { run({id: event.id.to_s, capacity: "lots"}, as: as_screen(permitted_account)) }
      .to have_field_errors(:capacity)
  end
end
```

There is also `"renders its declared output schema"`, and
`"a valid action registry"`. Put the registry one in a single spec. It checks
that every action loads, has a spec file and a valid input schema, and that
the committed catalogue is up to date.

### Generators

```sh
bin/rails g action Event::Update                  # a verb from the table
bin/rails g action Event::Archive --kind change   # any other verb
bin/rails actions:catalogue                       # rewrite config/actions.json
```

The generator writes the action, its locale entry and its spec. To change
the templates, copy them to `lib/templates/action/action.rb.tt` and
`lib/templates/rspec/action/action_spec.rb.tt`.

`config/actions.json` is the **catalogue**: every action as callers see it.
Commit it, so a change to any action's name or input shows up in review.

## Configuration

Every setting has a default that works for a plain Rails app. Set only what
you need:

```ruby
# config/initializers/actions.rb
Saltbox::Actions.configure do |config|
  config.app_name = "Events"   # used in tool titles and default messages
  config.instructions = "Events keeps a team's events. Use find_action for anything not listed."

  # Run each call inside your own context: tenant, time zone, a fresh user.
  config.around_invocation { |caller, run| Current.set(user: caller.account) { run.call(caller) } }

  # Hear about every changed record, inside the transaction.
  config.on_changes { |changes, invocation| EventLog.record(changes, invocation.caller) }

  # Run something once the change has committed. Never runs on rollback.
  config.after_change { |invocation, result| }

  config.feature_enabled { |key, caller| Flipper.enabled?(key, caller.account) }
  config.permissions_held { |caller| caller.account.permission_keys }

  # Turn your own errors into ones callers see.
  config.map_error("Events::Locked") { |error| Saltbox::Actions::Error.new(error.message, code: :locked) }

  # Add a boot check of your own.
  config.check_action { |action| action.description ? [] : ["write a description"] }
end
```

Other settings include `scopes` (default `api:read` and `api:write`),
`actions_path`, `catalogue_path`, `default_connections`, `enforce_confirm`
with `confirm` (see Connections), `error_format` and `result_format`. See `lib/saltbox/actions/configuration.rb` for each one.

## Known limits

- The unknown-action message always names `/api/v1/actions`, even if you
  mount the controller somewhere else.
- `returns` is in the catalogue and in specs, but is not yet sent to MCP
  clients as the tool's output schema. On a list with a summary, `returns`
  describes the view screens get; check an agent's result with
  `match_output_schema(described_class.summary_output_schema)`.
- A literal `%` in a default error message must be written `%%`.
- Configuration is set once, at boot. Changing it while requests run is not
  supported.

## Contributing

Bug reports and pull requests are welcome on GitHub. The specs run against a
small Rails app in `spec/rails_app`, with Pundit and ActionPolicy:

```sh
bundle install
bundle exec rspec
bundle exec standardrb
bundle exec rake catalogue   # rewrite the test app's actions.json
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).
