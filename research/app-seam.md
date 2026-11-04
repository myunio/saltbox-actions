# The app seam: how an app shapes saltbox-actions (1.3 design)

In 1.3 the initializer holds settings only, and what an app adds goes in its
ApplicationAction, written the way ApplicationController is written: callbacks,
`rescue_from`, and the method names PaperTrail and acts_as_tenant already use
in controllers. All 17 block settings in `Configuration` go. Three new adapters
(`:acts_as_tenant`, `:flipper`, `:pagy`) do what each app wrote by hand, and
change events reach the app as the `changes.saltbox_actions` notification the
gem already sends.

| | 1.2 | 1.3 |
|---|---|---|
| Blank app on Pundit: initializer, base class, one action | 12 lines | 12 lines |
| The same app, multi-tenant, on Flipper and PaperTrail | 12 lines, plus `around_invocation`, `feature_enabled` and `around_perform` blocks | 12 lines, with three more adapter names |
| Unio's initializer | 175 lines, 12 hook blocks and 2 lambdas | 65 lines, all settings |
| Unio, every file of the seam | 287 lines (158 code) in 3 files | 288 lines (146 code) in 7 files |
| Outport's initializer | 44 lines, 6 hook blocks | 31 lines, all settings |
| Outport, initializer and ApplicationAction | 211 lines (113 code) | 228 lines (114 code) |

Unio's total barely moves because most of what its hooks held is Unio's own
behaviour: which token is still good, what `Current` holds, the chat's gate,
its events and its activity log. That code stays in Unio. What leaves is the
gem's machinery around it: the `run` lambdas, the contracts each block had to
honour, and the tenant, feature-flag, audit and paging code every app would
write the same way. Section 5 says where each line went.

There is no app-owned caller class. A class like ApplicationCable::Connection
would also hold the caller's set-up, but it would bring back
`app/actions/application_action/caller.rb` and `context.rb`. Steve turned
those down in the #1590 review ("I'm seeing the same pattern ... I just don't
like it") and settled on Unio keeping only ApplicationAction and
saltbox_actions.rb. So the caller stays the gem's, and what an app says about
its callers sits in ApplicationAction, as a controller's sits in
ApplicationController.

Line counts are `wc -l`. Code lines are lines that are neither blank nor only a
comment. Every 1.3 file below passed `ruby -c`. None of them has run: gem 1.3
does not exist yet.

## 1. The principle

**Settings are data.** Inside `Saltbox::Actions.configure`, each line assigns a
value: a string, symbol, number, boolean, or an array or hash of those. There
are no hooks, no lambdas, and no method that takes a block. The `configure`
block itself is only the container, as `Devise.setup do |config|` is for
Devise's settings-only initializer
(`devise-5.0.4/lib/generators/templates/devise.rb:11`).

**Everything else is ordinary Rails code in ApplicationAction**, in the idiom
Rails uses for the same job:

| What the app adds | 1.3 idiom | The Rails precedent |
|---|---|---|
| Work around every call, actions list and search | `before_invocation`, `around_invocation`, `after_invocation` | `around_action` in ApplicationController (`actionpack-8.1.4/lib/abstract_controller/callbacks.rb:233`), on ActiveSupport::Callbacks (`activesupport-8.1.4/lib/active_support/callbacks.rb:903`) |
| Work around the action's own work | `before_perform`, `around_perform`, `after_perform` | Active Job's callbacks of the same names (`activejob-8.1.4/lib/active_job/callbacks.rb:50, 69, 102`) |
| Work once a change has committed | `after_commit` | Active Record's `after_commit` (`activerecord-8.1.4/lib/active_record/transactions.rb:285`) |
| Who the caller is now | `refresh_caller`, a method the gem calls | Pundit calls `pundit_user` (`pundit-2.5.2/lib/pundit/authorization.rb:51`); Devise calls `active_for_authentication?` (`devise-5.0.4/lib/devise/models/authenticatable.rb:89`) |
| How an error reaches the caller | `rescue_from` | ActiveSupport::Rescuable (`activesupport-8.1.4/lib/active_support/rescuable.rb:53`), as Pundit's README rescues `Pundit::NotAuthorizedError` (`pundit-2.5.2/README.md:507`) |
| The words of a message | I18n under `actions.errors`, each with a default | The gem's own `actions.errors.not_in_lookup_list` (`lib/saltbox/actions/permitting.rb:66`) |
| A library the app uses | an adapter, named in `config.adapters` | as 1.0 does for Pundit and PaperTrail |
| Something to listen to | `ActiveSupport::Notifications` | `changes.saltbox_actions`, which the gem already sends (`lib/saltbox/actions/invocation.rb:177`) |

**One-line adapters.** Each is a name in `config.adapters`:

- `:pundit` and `:action_policy` (existing): each also declares `rescue_from`
  for its own refusal (`Pundit::NotAuthorizedError`,
  `ActionPolicy::Unauthorized`), so a refusal is `forbidden`.
- `:acts_as_tenant` (new): every call runs in the caller's tenant, which is
  `current_tenant`. By default `current_tenant` is the person's tenant
  association: the name acts_as_tenant records (`ActsAsTenant.tenant_klass`,
  `acts_as_tenant-2.2.2/lib/acts_as_tenant.rb:45`), read when the person's
  model is tenanted. A system caller keeps the tenant around it, such as a
  job's. `current_tenant` is acts_as_tenant's own helper name
  (`acts_as_tenant-2.2.2/lib/acts_as_tenant/tenant_helper.rb:3`).
- `:flipper` (new): an action's `feature` is on when
  `Flipper.enabled?(key, *actors)` says so. The actors are the caller's person
  and the current tenant, each only when it responds to `flipper_id`
  (`flipper-1.4.2/lib/flipper/types/actor.rb:4`), because Flipper raises for any
  other object (`actor.rb:15`). Flipper counts a feature as on when it is on for
  any one of the actors (`flipper-1.4.2/lib/flipper/gates/actor.rb:28`). Unio's
  Account has no `flipper_id` and its Org has one, so Unio's gate stays
  union-only, exactly as now.
- `:paper_trail` (changed): wraps `perform` in `PaperTrail.request` with
  `whodunnit: user_for_paper_trail` and `controller_info: info_for_paper_trail`.
  PaperTrail's own controller methods have the same names and defaults: the
  person's id, and `{}` (`paper_trail-17.0.0/lib/paper_trail/frameworks/rails/controller.rb:26, 51`).
- `:pagy` (new): lists page with Pagy, using Pagy's own `limit` and
  `client_limit` (`Pagy::OPTIONS`, `pagy-43.8.1/lib/pagy.rb:35`) for the default
  and largest page size. `Saltbox::Actions::Adapters::Lists::Pagy` is the list
  adapter when the app names none, and an app's own adapter can extend it.
- `:approvals` (changed): all of its settings are data. The agent's message is
  the I18n key `actions.errors.approval_needed`, with `%{user}`, `%{app}` and
  `%{url}`.
- Change events need no adapter: the gem instruments `changes.saltbox_actions`
  inside every change's transaction, and the app subscribes.

## 2. Where each hook goes

Every block setting in 1.2's `Configuration`, plus the two settings that
accepted a lambda:

| 1.2 setting | Set by | 1.3 | Why this home |
|---|---|---|---|
| `refresh_caller` | Unio, Outport | `refresh_caller`, a private method on ApplicationAction that returns the caller as they stand now. The gem calls it first, before every call, actions list and search. Its default reloads an Active Record person. It refuses a caller holding a credential (`credential_id` or `connection`) unless the app overrides it, so a token is never trusted unchecked. | A method the gem calls, as Pundit calls `pundit_user`. The 1.0 review found that nothing in the gem called 1.1's `Caller#refresh`; 1.2 made it a setting that `within` calls. 1.3 keeps the central call and drops the setting. |
| `around_invocation` | Unio, gem spec app | An `around_invocation` callback. The tenant itself comes from `:acts_as_tenant`. | `around_action` |
| `check_caller` | Unio | `before_invocation ..., if:`. Raising refuses the call. | `before_action ..., if:` |
| `around_perform` | Unio, Outport, gem spec app | Audit stamps come from `info_for_paper_trail` through `:paper_trail`. Other work around `perform` is an `around_perform` callback (Outport's request context). | PaperTrail's controller methods; Active Job's `around_perform` |
| `on_changes` | Unio, gem spec app | Deleted. The app subscribes to `changes.saltbox_actions`, whose payload gains `invocation_id`. The gem instruments it inside the change's transaction, after the changes are de-duplicated, so a subscriber sees exactly what `on_changes` saw. A subscriber's exception propagates out of `instrument` (`activesupport-8.1.4/lib/active_support/notifications/fanout.rb:37-42`), so the change rolls back with it. | `ActiveSupport::Notifications.subscribe` |
| `on_access_refused` | Unio, Outport | The gem raises `Error::OutsideAccess`, an `InsufficientScope` with the same code and status, carrying the action, its area and the level it needs. The app's `rescue_from` raises its own refusal in its place. | `rescue_from` |
| `after_change_commit` | Unio, Outport | `after_commit`, run through `ActiveRecord.after_all_transactions_commit` (`activerecord-8.1.4/lib/active_record.rb:573`), never on rollback. | Active Record's `after_commit` |
| `feature_enabled` | Unio | `:flipper` | Flipper's actor API |
| `validate_feature` | Unio | Deleted. An app that keeps a list of known keys checks its actions' keys in a spec; Unio's is three lines. | An app-wide rule is a spec |
| `permissions_held` | Outport, gem spec app | `self.permissions_held(caller)`, a class method on ApplicationAction. `[]` by default. | A method the gem calls |
| `schema_user` | Unio, gem spec app | `self.with_schema_user`, a class method on ApplicationAction that yields the person. Without it the policy is asked with no person, as now. | Methods that yield, such as `ActsAsTenant.with_tenant` (`acts_as_tenant.rb:109`) and `Time.use_zone` |
| `on_forbidden_fields` | Unio | The gem raises `Error::ForbiddenFields`, a `Forbidden` with the fields, worded by `actions.errors.forbidden_fields` and `actions.errors.forbidden_field`. An app that words it from its own data (Unio names the person's roles) rescues it. | I18n; `rescue_from` |
| `map_error` | Unio, Outport | `rescue_from`. The gem's own translations (`RecordNotFound`, `RecordInvalid`, `RecordNotDestroyed`, `DeleteRestrictionError`) become `rescue_from` lines in Base. Rescuable searches handlers last-first (`activesupport-8.1.4/lib/active_support/rescuable.rb:129`), so an app's own line for the same error wins, as `map_error` did. | `rescue_from` in ApplicationController |
| `confirm` | nobody | Deleted. `:approvals` is how a person approves an agent's `:confirm` call. Without it, the call is refused with `confirmation_required`, as now. | |
| `area_for` | gem spec app | Deleted. `areas` (data) is the one way to give each model's area. | |
| `check_action`, `check_registry` | nobody (gem specs) | Deleted. An app's own rule over its actions is a spec over `ApplicationAction::Registry.actions`. | |
| `max_array_items` as a lambda | Unio | A number, set at boot. Unio's `CoreConfig` already loads at boot (its `cors.rb:10` reads it). | A setting is a value |
| `page_size`, `max_page_size` | Unio | With `:pagy`, Pagy's own settings. Both stay for an app without Pagy. | One source for each value |
| `approvals` `message:`, `current_tenant:` | Unio, gem spec app | `message:` becomes the I18n key, and `approvals` gains `name:` (the method that names the person in it, `to_s` by default) and `url:` (where they approve). `current_tenant:` goes: approvals are kept in acts_as_tenant's current tenant, which `:acts_as_tenant` sets for every call. | I18n; data |

## 3. What happens in a call

`Invocation#call` in 1.3:

1. The entry point builds the caller from its credential, as now.
2. The action is built with `current_caller` only. Its input comes in step 4.
3. The invocation callbacks run, in this order:
   - the gem's own, first: `refresh_caller`. Its result replaces `current_caller` on the action and `Invocation#caller`, where `confirm!`, approval matching, the notification payload and `InvocationJob` read it;
   - each declared adapter's (`:acts_as_tenant` sets the tenant);
   - the app's, in the order ApplicationAction declares them. A `before_invocation` declared after an `around_invocation` runs inside it.
4. Inside them come the refusals, in their fixed order (feature, agents, access, scope, permission). Then the input is checked against the schema, assigned to the action, and validated.
5. `confirm!` runs for an agent's call to a `:confirm` action.
6. The work runs. A read runs `perform_now`. A change runs it in a savepoint transaction on its model's connection. Either way the perform callbacks, including the `:paper_trail` adapter's `around_perform`, wrap the record lookup, `perform` and the authorization checks. For a change, the gem then collects and de-duplicates the changed records, instruments `changes.saltbox_actions` with them while the transaction is still open, and queues the `after_commit` callbacks.
7. An exception in steps 4 to 6 goes to the action's `rescue_from` handlers inside the invocation callbacks. A handler therefore still has the caller's tenant, time zone and `Current`; Unio's refusal record needs the union. This differs from a controller, where `rescue_from` wraps the callbacks. An error raised by `refresh_caller` or by an invocation callback is the app's own refusal and goes straight to the entry point.
8. What leaves the call is a gem `Error`, which the entry point renders, or a bug, which stays a 500.

**Actions list and search** (`Saltbox::Actions.within(caller)`, used by
`find_action`, the actions list, the catalog's per-caller listing,
`Arguments.check`, the test matchers and Unio's record-changes channel) have no
action. The gem builds an instance of the app's base class
(`config.base_class`) with the caller and no input, runs the same invocation
callbacks around the block, and yields the refreshed caller. Devise does the
same kind of thing: its controllers subclass the app's
(`DeviseController < Devise.parent_controller.constantize`,
`devise-5.0.4/app/controllers/devise_controller.rb:4`), so the app's callbacks
run for Devise's pages. Gem 1.2 already builds that instance without error
(tested; see "What was tested").

The contract for an invocation callback: it uses the caller (`current_caller`,
`current_user`, `current_tenant`), never the action's own declarations such as
`action_name` or `area`, because a list or search has no action.

## 4. The blank-app test

The whole seam for an app that authorizes with Pundit: 12 lines.

```ruby
# config/initializers/saltbox_actions.rb
Saltbox::Actions.configure do |config|
  config.adapters = [:pundit]
  config.app_name = "Shelf"
end
```

```ruby
# app/actions/application_action.rb
class ApplicationAction < Saltbox::Actions::Base
end
```

```ruby
# app/actions/books/update_action.rb
class Books::UpdateAction < ApplicationAction
  def perform
    book.update!(permitted_attributes(book))
    render :show
  end
end
```

It runs from the console:

```ruby
Books::UpdateAction.perform_now(caller: ApplicationAction::Caller.screen(User.first), id: Book.first.id, title: "Dune")
```

The other things it needs are what the app already has:

- `gem "saltbox-actions"` and `gem "pundit"` in the Gemfile;
- `BookPolicy` with `update?` and `permitted_attributes`, which the action
  authorizes with and builds its input from;
- the scaffold's `app/views/books/show.json.jbuilder` for `render :show`;
- the `Book` and `User` models.

A multi-tenant app on Flipper and PaperTrail writes the same 12 lines, with
`:acts_as_tenant, :flipper, :paper_trail` added to `config.adapters`. In 1.2 it
also needed `around_invocation`, `feature_enabled` and `around_perform` blocks.

Untested: no app has booted these files. Gem 1.3's generator spec (section 8)
boots them in its dummy app.

## 5. Unio after

| File | 1.2 | 1.3 |
|---|---|---|
| `backend/config/initializers/saltbox_actions.rb` | 175 (112 code) | 65 (38 code) |
| `backend/app/actions/application_action.rb` | 63 (25 code) | 149 (71 code) |
| `backend/app/models/tabular_content/action_adapter.rb` | 49 (21 code) | 36 (12 code) |
| `backend/lib/unio/record_changes/subscribers/publish_action_changes.rb` | | 24 (18 code), new |
| `backend/config/initializers/rails_event_store.rb` | | 5 lines added (1 code) |
| `backend/config/locales/actions.en.yml` | | 5 lines added (3 code) |
| `backend/spec/actions/application_action/registry_spec.rb` | | 4 lines added (3 code) |
| **Total** | **287 (158 code)** | **288 (146 code)** |

### The initializer: 65 lines, all settings

```ruby
# Unio's settings for the action layer (the saltbox-actions gem), all data.
# Who is calling, and how each call is set up for them, is
# ApplicationAction::Caller; what every action shares is ApplicationAction.
Saltbox::Actions.configure do |config|
  # Pundit authorizes every action and acts_as_tenant holds it to the
  # caller's union; the API controller, MCP and the chat's RubyLLM tools run
  # them; PaperTrail records who changed what; Flipper turns a feature on per
  # union; Pagy pages lists; approvals keep an agent's call to a :confirm
  # action until the person approves it.
  config.adapters = [:pundit, :acts_as_tenant, :controller, :mcp, :ruby_llm_tool, :paper_trail, :flipper, :pagy, :approvals]
  config.app_name = "Unio"

  # Each area a connection is granted and a change is announced to, with
  # its models. A change announcement says only which area changed, unless
  # the area names the models whose record, person and agent the union's
  # staff may all see (metadata_models). read_action admits a person.
  config.areas = {
    "events" => {models: %w[Event Event::Type], metadata_models: %w[Event], read_action: "list_events"},
    "members" => {models: %w[Member Member::Status Member::PortalAccess Member::PortalAccessChange Member::AvailabilityStatus
      Member::Specialization SpecializationAssignment AvailabilityList::Entry DuesCoverageEntry], read_action: "list_members"},
    "dues" => {models: %w[Payment Allocation Invoice Invoice::LineItem Customer LedgerAccount], read_action: "list_payments"},
    "contacts" => {models: %w[Address PhoneNumber EmailAddress ContactAssignment]},
    "documents" => {models: %w[Document Document::Assignment]}
  }
  config.require_area = true
  # find_action with no query lists these areas first, as staff think of them.
  config.area_order = %w[events members dues]
  # Short lists the union keeps to choose from: any staff member picks from
  # them in a dropdown, so a field names an entry by id or by name, without
  # the Pundit scope.
  config.lookup_lists = %w[Event::Type MembershipType MembershipState Document::Type PaymentMethod]
  # A list action runs the staff screen's TabularContent table.
  config.list_adapter = "TabularContent::ActionAdapter"
  config.max_array_items = CoreConfig.bulk_array_param_limit

  config.instructions = <<~TEXT.freeze
    Unio is a union's membership and office system. You act as the signed-in staff member, in one union,
    with exactly their permissions; whoami says who that is, which union, its time zone and today's date,
    whether this connection may make changes, and in which areas (connection_areas: none, read or change).

    Finding things: the listed tools cover the most common work. For anything else, call find_action with the
    request in plain words, then run the action it returns with the run tool it names (run_read_action,
    run_change_action or run_destructive_action). find_action with no query lists everything this
    connection can do. Records are named by id; list or search first to find one.

    Doing things: before running an action find_action marks confirm_first, say what will change and get a
    yes. For other changes, say what you are about to change and go ahead. Never run anything destructive
    without a yes.
    Dates are YYYY-MM-DD and times HH:MM, in the union's time zone from whoami.

    Errors come back with a code (not_found, forbidden, human_required, insufficient_scope,
    validation_failed) and a message to act on. not_found means the record does not exist or the person
    cannot see it. human_required means only the person can do this, in Unio: tell them so.
    insufficient_scope with details.area means this connection's areas do not reach the action: details.needs
    is the level it needs and details.asked says whether the person was asked to allow it. Tell them, and
    try again once they have. None is a problem to work around.
  TEXT

  # An agent's call to a :confirm action runs once the person has approved
  # that exact call in Unio, in the union of the call; until then it is
  # refused, and the person finds the request at url (the words are
  # actions.errors.approval_needed in config/locales/actions.en.yml).
  config.approvals = {user: "Account", name: :full_name, tenant: "Org", connection: "Oauth::Connection",
    url: "#{CoreConfig.new.frontend_url}/settings/connections"}
end
```

### ApplicationAction: 149 lines

```ruby
# The base class for actions. An action is one thing a person can do in
# Unio, such as updating an event. It is written once, and every way into
# Unio runs the same class:
# - the staff screens;
# - the REST API at /api/v1/actions;
# - the CLI;
# - MCP, for AI agents;
# - the in-app chat assistant.
#
# An action works like a controller action: its attributes are its input,
# #perform does the work, then renders a Jbuilder view with render or head.
#
# Most settings come from the class name, the way a controller's do:
# Events::UpdateAction, in app/actions/events/, works on Event, asks
# EventPolicy#update? and is the MCP tool update_event. Its verb, update,
# says the rest: a change, on one record, that agents may run. A member
# action's record is loaded through its Pundit scope and authorized before
# #perform, as @event and the reader event. Settings the name and the verb
# cannot give are declared at the top of the class.
#
# The layer itself is the saltbox-actions gem, with its settings for Unio in
# config/initializers/saltbox_actions.rb. Here, as ApplicationController
# does for a request, is what every call shares: who the caller is now, the
# account, union and time zone it runs in, the chat's own gate, its audit
# stamp, what a connection's change or refusal leaves in its activity, how an
# error reaches the caller, and each listed model's summary.
#
# @example
#   class Events::UpdateAction < ApplicationAction
#     def perform
#       event.update!(permitted_attributes(event))
#       render :show
#     end
#   end
class ApplicationAction < Saltbox::Actions::Base
  # Unio's verbs beside the gem's list, show, create, update and
  # delete: each works on one record, and doing it again changes nothing.
  define_verb :cancel, :reinstate, :publish, kind: :change, on: :member, idempotent: true

  around_invocation :act_as_account
  before_invocation :require_assistant_chat, if: -> { current_caller.surface.assistant? }
  after_commit :record_connection_change, if: -> { current_caller.connection }

  rescue_from Unio::Errors::BaseError, with: :refuse_with_domain_error
  rescue_from Error::OutsideAccess, with: :ask_for_access
  rescue_from Error::ForbiddenFields, with: :name_roles

  # What a list sends agents for each record: enough to pick one, with no
  # file links; the model's show action gives the rest. A person on a staff
  # screen gets the list's full view.
  summary Event, :id, :title, :start_date, :cancelled, :end_date, :visibility,
    start_time: ->(event) { event.start_time&.to_fs(:hour_minute) },
    state: ->(event) { event.current_state },
    end_time: ->(event) { event.end_time&.to_fs(:hour_minute) },
    event_type: ->(event) { event.event_type&.name }
  summary Member, :id, :code, :full_name, :slug,
    full_name_last_first: ->(member) { member.full_name(last_name_first: true) },
    current_state: ->(member) { member.provisioning_state },
    membership_type: ->(member) { member.current_member_status&.membership_type&.name },
    membership_state: ->(member) { member.current_member_status&.membership_state&.name },
    unit: ->(member) { member.org_unit&.label },
    region: ->(member) { member.region&.name },
    city: ->(member) { member.addresses.find(&:primary)&.city }
  summary Payment, :id, :payment_number, :paid_on, :amount_cents, :amount_currency, :status, :member_id, :payment_source,
    :reference_number, :voided_at,
    payment_method: ->(payment) { payment.payment_method&.name },
    employer: ->(payment) { payment.employer&.name }

  # Who a schema is built for where there is no caller, such as the
  # committed catalog: an account holding every permission, in the staff
  # app. Each caller's own schema lists the fields their policy permits them.
  #
  # @yieldparam user [Account]
  # @return [Object] the block's value
  def self.with_schema_user
    everyone = Account.new
    everyone.define_singleton_method(:effective_permission_set) { :all }
    Current.set(app_context: "main") { yield everyone }
  end

  private

  # The caller as they stand now. A connection's token is checked again
  # (Oauth::Bearer). A staff member's account is reloaded outside any union,
  # and must still be active with access to the staff app.
  def refresh_caller
    return Oauth::Bearer.revalidate!(current_caller) if current_caller.credential_id || current_caller.connection
    fresh = ActsAsTenant.without_tenant { Account.uncached { Account.includes(:user, :org).find_by(id: current_user&.id) } }
    raise Error::Unauthorized unless fresh&.user&.active?
    fresh.org.with_tenant { Account.uncached { raise Error::Unauthorized unless fresh.main_app_access? } }
    current_caller.with(user: fresh)
  end

  # The person, the staff app context, the agent, surface and connection, a
  # fresh permission cache and the union's currency, read uncached, in the
  # union's time zone, with every query held to the union, which the
  # :acts_as_tenant adapter has set. Current.set restores what was set
  # before; session= assigns account too, so session comes first.
  def act_as_account(&)
    org = current_user.org
    ActiveRecord::Base.uncached do
      Current.set(session: nil, account: current_user, app_context: "main", agent: AgentVia.for(current_caller),
        surface: current_caller.surface, connection: current_caller.connection, account_permission_cache: nil) do
        Time.use_zone(org.time_zone) do
          Unio::TenantStrictness.enforce { Current.set(org_currency: OrgSetting.fetch("general.currency", nil, org), &) }
        end
      end
    end
  end

  # Chat needs its own permission and the union's assistant_chat feature,
  # on top of whatever the action's policy asks.
  def require_assistant_chat
    raise Error::Forbidden unless current_user.has_permission?("access:assistant_chat")
    raise Error::NotFound unless Flipper.enabled?("assistant_chat", current_user.org)
  end

  # Both names on every audit entry, and the agent's stamp (AgentVia):
  # versions.agent keeps the name alone, versions.agent_via the whole stamp.
  def info_for_paper_trail
    {agent: current_caller.agent_name, agent_via: AgentVia.for(current_caller), surface: current_caller.surface,
     connection_id: current_caller.connection&.id, invocation_id:}
  end

  # What a connection changed, once it has committed, for Settings ›
  # Connected apps. It may run after the call has ended, so it sets the
  # union itself.
  def record_connection_change
    current_user.org.with_tenant { Oauth::ConnectionActivity.record_change!(current_caller, self.class, result.body) }
  end

  # A list's invalid filter value is the caller's to fix; any other domain
  # refusal keeps its own code and status.
  def refuse_with_domain_error(error)
    raise Error::ValidationFailed, error.message if error.code.to_s == "invalid_filter"
    raise Error.new(error.message, code: error.code, status: error.status)
  end

  # A connection runs only what its areas allow. The refusal is kept on the
  # connection, and the person is asked when they could allow it.
  def ask_for_access(error) = raise(Oauth::ConnectionActivity.record_refusal!(current_caller, error.action).refusal)

  # A field the person sent but may not change, named with their roles.
  def name_roles(error)
    roles = current_user.role_names_in_context.to_sentence.presence || "none"
    raise Error::ForbiddenFields.new(I18n.t("actions.errors.forbidden_fields_for_roles", roles:, fields: error.fields.to_sentence),
      fields: error.fields)
  end
end
```

### The change-event subscriber: 24 lines, new

`lib/unio/record_changes/` already holds `Events::RecordChangedV1` and
`Subscribers::BroadcastRecordChange`, so the code that publishes the event goes
beside them.

```ruby
module Unio
  module RecordChanges
    module Subscribers
      # Publishes each record an action changed as a RecordChangedV1 event,
      # inside the action's transaction: Rails Event Store keeps events in
      # the same database, so a change and its event are saved together or
      # not at all. BroadcastRecordChange tells open screens once it commits.
      module PublishActionChanges
        # @param event [ActiveSupport::Notifications::Event] changes.saltbox_actions
        # @return [void]
        def self.call(event)
          action, caller, invocation_id = event.payload.values_at(:action, :caller, :invocation_id)
          event.payload.fetch(:changes).each do |record_type, record_id, _event_type|
            Rails.configuration.event_store.publish(Events::RecordChangedV1.new(data: {
              org_id: caller.user.org_id, area: ApplicationAction::Areas.for_model!(record_type), record_type:, record_id:,
              change: action.action_name, account_id: caller.user.id, agent: caller.agent_name, surface: caller.surface,
              invocation_id:, occurred_at: Time.current.iso8601
            }))
          end
        end
      end
    end
  end
end
```

Added to `config/initializers/rails_event_store.rb`, outside its `to_prepare`
block. The block subscribes once and looks the subscriber up on every event,
so a code reload never leaves a stale one. A one-argument block receives an
`ActiveSupport::Notifications::Event`
(`activesupport-8.1.4/lib/active_support/notifications/fanout.rb:350-353`).

```ruby

# Each record an action changes, as a RecordChangedV1 event in the action's
# own transaction. Subscribed once; the subscriber is looked up on each event,
# so a code reload never leaves a stale one.
ActiveSupport::Notifications.subscribe("changes.saltbox_actions") { |event| Unio::RecordChanges::Subscribers::PublishActionChanges.call(event) }
```

### Words, the list adapter and the feature-key check

Added under `en.actions.errors` in `config/locales/actions.en.yml`:

```yaml
      # A field a person's role may not change, and what an agent is told
      # until the person approves its call to a :confirm action.
      forbidden_field: your role can't change this
      forbidden_fields_for_roles: "Your role, %{roles}, can't change %{fields}."
      approval_needed: "%{user} must approve this in Unio first, under Settings, Connections (%{url}). Then call it again with the same arguments."
```

`TabularContent::ActionAdapter`: paging moves to `:pagy`, and the table's own
methods stay.

```ruby
# frozen_string_literal: true

module TabularContent
  # How actions run a TabularContent table, the same table a staff screen
  # shows (the gem's config.list_adapter). Pages come from the gem's :pagy
  # adapter; this adds the table's filters, search and metadata.
  #
  # @example
  #   class Events::ListAction < ApplicationAction
  #     table TabularContent::Event
  #   end
  module ActionAdapter
    extend Saltbox::Actions::Adapters::Lists::Pagy

    class << self
      # @param table [Class<TabularContent::Base>]
      # @return [Hash{Symbol=>Hash}] each filter's key and JSON schema
      def filters(table) = table.definition.filters.to_h { [it.key, it.action_schema] }

      # @param table [Class<TabularContent::Base>]
      # @return [Boolean]
      def search?(table) = !!table.definition.search&.enabled

      # @return [ActiveRecord::Relation] the account's records, searched, sorted and filtered
      def query(table, user:, params:) = table.query(account: user, params:)

      # @return [Hash] every filter with its values, and every sort
      def metadata(table, user:, params:) = table.metadata_payload(params:, account: user)

      # @param pagination [Pagy]
      # @param metadata [Hash, nil]
      # @return [Hash] the :pagy adapter's meta.pagination, and meta.tabular when there is a table's metadata
      def list_meta(pagination, metadata) = super.merge({tabular: metadata}.compact)
    end
  end
end
```

Added to `spec/actions/application_action/registry_spec.rb`, in place of
`validate_feature`:

```ruby

  it "declares only feature keys Unio knows" do
    described_class.actions.filter_map(&:feature).uniq.each { Unio::FeatureFlags::Registry.validate_key!(it) }
  end
```

### Where each hook's code went

Code lines, 1.2 to 1.3:

| 1.2 hook | Code lines | Where in 1.3 |
|---|---|---|
| `refresh_caller` | 7 → 7 | `refresh_caller`: Unio's rules for a token and a staff account |
| `around_invocation` | 18 → 11 | `around_invocation :act_as_account`. The tenant moves to `:acts_as_tenant`. The `run` lambda goes. The `ensure` that put `Current.account` back after two nested `Current.set` calls goes too, because one `Current.set` lists `session` before `account` and restores them in that order (`activesupport-8.1.4/lib/active_support/core_ext/object/with.rb:26-38`). |
| `check_caller` | 5 → 5 | `before_invocation :require_assistant_chat` |
| `around_perform` | 5 → 4 | `info_for_paper_trail`. The call into the gem's PaperTrail helper and its `run` lambda go. |
| `on_changes` | 10 → 19 | the subscriber, plus its subscription line. The extra lines are the module wrappers of a file in `lib/`. |
| `on_access_refused` | 1 → 2 | `rescue_from Error::OutsideAccess` |
| `after_change_commit` | 5 → 4 | `after_commit :record_connection_change` |
| `feature_enabled` | 1 → 0 | `:flipper` |
| `validate_feature` | 1 → 3 | the registry spec |
| `schema_user` | 5 → 5 | `self.with_schema_user` |
| `on_forbidden_fields` | 5 → 8 | `rescue_from Error::ForbiddenFields`, plus two locale lines |
| `approvals` `message:` lambda | 4 → 1 | one locale line; `name:` and `url:` join the `approvals` hash |
| `map_error` | 4 → 5 | `rescue_from Unio::Errors::BaseError` |
| `page_size`, `max_page_size` | 2 → 0 | `:pagy` |

Outside the hooks, `TabularContent::ActionAdapter` loses its paging (21 → 12
code lines), and five summary lambdas that only called a method of the same
name become plain names. The gem already reads a name with `public_send`
(`lib/saltbox/actions/summary.rb`).

### What stays Unio's, and why

- **`refresh_caller`**: which tokens are still good (`Oauth::Bearer`) and which
  accounts may still act (active, with staff-app access). Only Unio knows its
  tokens and its rules for staff.
- **`act_as_account`**: what Unio's `Current` holds (session, account, app
  context, agent stamp, permission cache, currency), the union's time zone, and
  Unio's strict-tenant rule (`Unio::TenantStrictness`). Rails sets a request's
  time zone the same way, with `Time.use_zone` in an around callback.
- **`require_assistant_chat`**: the chat's own permission and feature flag are
  Unio product rules.
- **The activity log** (`ask_for_access`, `record_connection_change`): Unio's
  `Oauth::ConnectionActivity` table, its notification to the person and its
  Settings › Connected apps screen.
- **The change event**: `RecordChangedV1` is Unio's Rails Event Store event.
- **`refuse_with_domain_error`**, **`name_roles`**, **`with_schema_user`**,
  **`info_for_paper_trail`**: Unio's error codes, its roles, its permission
  model and its `versions` columns.

## 6. Outport after

Outport's ApplicationAction is mostly its bridge to its own Base, which keeps
its catalogue entry, argument checks and errors unchanged while its areas move
to the gem one at a time: `invoke`, `domain`, `required`, `input_schema`,
`arguments`, `validate_arguments`, `permitted?`, `discovery_policy`,
`available_to?`, `paginated`, `returns`, `scope`, `cli_hints`, `definition`,
the stubs, `refusal` and `authorize!`. That bridge is 167 lines (89 code) in
1.2 and 1.3 alike, and it goes when Base does. The seam is the rest.

| File | 1.2 | 1.3 |
|---|---|---|
| `config/initializers/saltbox_actions.rb` | 44 (24 code: 12 settings, 12 in hook blocks) | 31 (12 code, all settings) |
| `app/actions/application_action.rb` | 167 (89 code, all bridge) | 197 (102 code: the bridge, plus 13 of seam) |
| **Total** | **211 (113 code)** | **228 (114 code)** |

### The initializer: 31 lines, all settings

```ruby
# saltbox-actions settings, first written by `rails g actions:install`. Every setting
# has a default that works for a plain Rails app; see
# Saltbox::Actions::Configuration for each one.
#
# Actions on the shared action layer (Actions::ApplicationAction) keep Base's
# contract: Outport's surfaces, errors and envelope, every action open to
# agents within their connection's areas, and permissions deciding only the
# list. Who is calling is Actions::ApplicationAction::Caller.
Saltbox::Actions.configure do |config|
  # The optional adapters to load: only those listed load. Outport serves the
  # API, /mcp and the assistant itself, through Actions::Invocation, and keeps
  # its own audit trail, so it declares only the authorization adapter.
  config.adapters = [
    # :pundit,          # authorizes each action with the model's Pundit policy (gem "pundit")
    :action_policy     # authorizes each action with the model's ActionPolicy policy (gem "action_policy")
    # :controller,      # serves every action as a JSON API, from one controller that includes it (no gem)
    # :mcp,             # serves every action to AI agents over the Model Context Protocol (gem "mcp")
    # :ruby_llm_tool,   # gives an in-app RubyLLM chat the actions as tools (gem "ruby_llm")
    # :invocation_job,  # runs an action later as an Active Job, for perform_later (no gem)
    # :paper_trail,     # stamps each PaperTrail version an action writes (gem "paper_trail")
  ]

  config.app_name = "Outport"
  config.base_class = "Actions::ApplicationAction"
  # app/actions also holds Base's actions and shared code (Schemas, Invocation).
  config.strict_action_paths = false
  config.surfaces = %w[web api v1 mcp assistant]
  config.enforce_permissions = false
  config.error_format = :type
  config.result_format = :envelope
end
```

### ApplicationAction: what the seam adds

```diff
--- 1.2 (out-1200-saltbox-actions-1-1)
+++ 1.3
@@ -27,6 +27,15 @@
   class ApplicationAction < Saltbox::Actions::Base
     include Pagination
 
+    around_perform :within_request
+    after_commit :record_activity, if: -> { current_caller.connection }
+
+    # Invocation answers every other error, as it does for Base's actions.
+    # Declared first: a later rescue_from is found first, so the area refusal
+    # below still gets its own answer.
+    rescue_from(StandardError) { |error| raise error }
+    rescue_from Saltbox::Actions::Error::OutsideAccess, with: :refuse_area
+
     class << self
       # Runs +action+ through the gem for Invocation, which has already
       # checked that someone is signed in. +credential+ is the bearer
@@ -43,6 +52,9 @@
         raise refusal(error, action)
       end
 
+      # The keys the person holds, for actions that declare `permission`.
+      def permissions_held(caller) = ::Authorization::Context.new(user: caller.user).effective_permission_keys(include_resource_scoped: true)
+
       # The area its folder names (Agents::Areas), as on Base.
       def domain = name.split("::").second.underscore
 
@@ -155,6 +167,24 @@
 
     private
 
+    # The person as they stand now, as Invocation#admit_person! reloads them.
+    def refresh_caller
+      fresh = User.active.find_by(id: current_user.id) or raise Error::Forbidden
+      current_caller.with(user: fresh)
+    end
+
+    # Current, the CRM change source and PaperTrail for the person, as
+    # Invocation sets them for Base's actions.
+    def within_request(&) = Invocation.within_request(person: current_user, service: nil, surface: current_caller.surface.to_sym,
+      credential: current_caller.connection, &)
+
+    # What a connection changed, once it has committed.
+    def record_activity = ::Agents::Activity.record_change!(current_caller.connection, self.class, result.body)
+
+    # The connection's areas stop short: the refusal is kept and the person
+    # asked, with Base's AreaNotAllowed error.
+    def refuse_area(error) = raise(Invocation.area_refusal(current_caller.connection, error.action))
+
     # As Base#authorize!: a refusal on a record is Error::Hidden, which the
     # run endpoint and /mcp answer as a missing record.
     def authorize!(record = :__undef__, **options)
```

- **Rescue order.** `rescue_from(StandardError) { |error| raise error }` takes
  the place of `map_error("StandardError") { nil }`. Every error raised in a
  gem action reaches Outport's own Invocation, which turns it into its `Error`
  with `record_errors:` details as it does for Base's actions. The pass-through
  is declared before the `OutsideAccess` handler because Rescuable tries the
  last declaration first.
- **`within_request`** keeps Outport's request context (`Current`, the CRM
  change source, `PaperTrail.request`) in the method its Invocation already
  uses, so both kinds of action set up alike. Outport does not declare
  `:paper_trail` for the same reason.

<details>
<summary>Outport's ApplicationAction in full: 197 lines</summary>

```ruby
module Actions
  # The base for actions on the shared action layer, the saltbox-actions gem
  # (OUT-1200): the gem's declarations, its Invocation and its ActionPolicy
  # adapter (declared in config/initializers/saltbox_actions.rb), with Outport's
  # catalogue entry, argument checks and errors, so the API, /mcp and `out`
  # see no change. Areas move here one at a time
  # (feedback first); Base serves the rest until they do, and Invocation
  # hands these to the gem. How to write one: project/guides/actions.md.
  #
  #   class Actions::Feedback::ListFeedbackAssignees < Actions::ApplicationAction
  #     action_name "list_feedback_assignees"
  #     title "List people feedback can be assigned to"
  #     description "Use this when ... Returns ..."
  #     kind :read
  #     permission :everyone
  #     paginated
  #     output_schema Schemas::ASSIGNEE
  #     cli "feedback assignees list"
  #     summary :id, :name, :email
  #
  #     def perform
  #       authorize ::Feedback::Chat.new(user: current_user), :create?, with: ::Feedback::ChatPolicy
  #       ...
  #       render json: records, meta: meta
  #     end
  #   end
  class ApplicationAction < Saltbox::Actions::Base
    include Pagination

    around_perform :within_request
    after_commit :record_activity, if: -> { current_caller.connection }

    # Invocation answers every other error, as it does for Base's actions.
    # Declared first: a later rescue_from is found first, so the area refusal
    # below still gets its own answer.
    rescue_from(StandardError) { |error| raise error }
    rescue_from Saltbox::Actions::Error::OutsideAccess, with: :refuse_area

    class << self
      # Runs +action+ through the gem for Invocation, which has already
      # checked that someone is signed in. +credential+ is the bearer
      # sign-in, whose connection holds the agent's areas.
      def invoke(action, actor:, scopes:, surface:, credential:, arguments:)
        if actor.is_a?(ServicePrincipal)
          raise Error::Forbidden, "Services cannot use #{surface}" unless surface == :v1
          raise Error::Forbidden
        end
        caller = Saltbox::Actions::Caller.new(user: actor, surface: surface, scopes: scopes, connection: credential, access: credential&.access)
        result = Saltbox::Actions::Invocation.call(action: action, caller: caller, arguments: arguments)
        Result.new(data: result.body, meta: result.meta)
      rescue Saltbox::Actions::Error => error
        raise refusal(error, action)
      end

      # The keys the person holds, for actions that declare `permission`.
      def permissions_held(caller) = ::Authorization::Context.new(user: caller.user).effective_permission_keys(include_resource_scoped: true)

      # The area its folder names (Agents::Areas), as on Base.
      def domain = name.split("::").second.underscore

      # Attributes the caller must send, though they may be blank, as Base's
      # `required: true`. The gem's own required comes from a presence
      # validation, which answers a blank value itself; here the domain's own
      # check answers it, with the same error as on Base.
      def required(*names) = required_attributes.concat(names.map(&:to_s))

      def required_attributes = @required_attributes ||= []

      # The gem's schema with each description right after its type, as
      # Base writes it, so the catalogue and its version do not change.
      def input_schema(...)
        schema = super
        schema.merge("properties" => schema.fetch("properties").transform_values { |property| property.slice("type", "description").merge(property) },
          "required" => (schema.fetch("required") + required_attributes).uniq)
      end

      # Each attribute's schema and whether it is required, as
      # Actions::Arguments reads Base's arguments.
      def arguments
        schema = input_schema
        schema.fetch("properties").to_h { |name, property| [name, {schema: property, required: schema.fetch("required").include?(name)}] }
      end

      # Arguments as Base checks them, with v1's explicit nulls kept.
      def validate_arguments(arguments, caller)
        Arguments.new(self, keep_nulls: Invocation::KEEP_NULL_SURFACES.include?(caller.surface.to_sym), user: caller.user).validate!(arguments)
      end

      # Guests are refused after the scope, as on Base. Who else may run it
      # is the policy's to decide on each record; `permission` decides only
      # the actions list.
      def permitted?(user) = !user.guest?

      # As Base.discovery_policy: a policy rule asked before listing it.
      def discovery_policy(name = nil, rule = nil)
        name ? @discovery_policy = [name, rule.to_s] : @discovery_policy
      end

      def available_to?(authorization)
        return false if authorization.user&.guest?
        return false if (gate = discovery_policy) && !authorization.policy_allowed?(*gate)
        return false unless enabled_for?(authorization.user)
        permissions_met?(authorization.effective_permission_keys(include_resource_scoped: true))
      end

      # A list action: page and page_size, and meta.pagination as v1 reports it.
      def paginated
        @paginated = true
        attribute :page, :integer, description: "Page number, from 1"
        attribute :page_size, :integer, description: "Items per page, up to #{Base::PAGE_SIZE_LIMIT} (default #{Pagy::OPTIONS.fetch(:limit)})"
        validates :page, :page_size, numericality: {greater_than_or_equal_to: 1}, allow_nil: true
      end

      def paginated? = @paginated || false

      # Base's words: `returns` is the gem's output_schema, the data alone,
      # and output_schema is what every surface sends back, the envelope.
      alias_method :returns, :output_schema

      def output_schema(schema = nil) = schema ? super : Result.schema(returns, paginated: paginated?)

      # The token scope it needs, as Base names it.
      def scope = required_scope

      # The policies' context, as on Base: the person and their permissions.
      def authorization_context_for(user) = {user:, authorization: ::Authorization::Context.new(user:)}

      # Base's `out` hints: the gem's command, with the summary as its columns.
      def cli_hints = declared_cli&.merge(columns: summary&.names || [])&.transform_keys(&:to_s)

      # Base's catalogue entry, key for key, so `out` and the registry
      # version see no change.
      def definition(_user = :everyone)
        {
          "name" => action_name, "title" => title, "description" => description, "domain" => domain,
          "kind" => kind.to_s, "idempotent" => idempotent?, "scope" => scope,
          "permissions" => permissions.grep(String), "permissions_any_of" => permissions.grep(Array),
          "service_capabilities" => service_capabilities, "input_schema" => input_schema, "output_schema" => output_schema, "cli" => cli_hints
        }
      end

      # What Base offers that these do not use yet: per-person descriptions
      # and arguments, service tokens, guests, comment-level and other areas.
      def description_for(_user) = description
      def input_schema_for(_user) = input_schema
      def hidden_arguments(_user) = []
      def strict_arguments? = false
      def service_capabilities = []
      def guest_access? = false
      def comment_level? = false
      def agent_area_keys = nil
      def ownership_reason = nil

      private

      # The gem's own refusals as Base's errors, which every surface reports.
      def refusal(error, action)
        case error.type
        when "not_found" then Error::NotFound.new
        when "insufficient_scope" then Error::InsufficientScope.new(action.scope)
        when "validation_error" then Error::Invalid.new(error.message, details: error.as_json.dig("error", "details"))
        when "forbidden", "human_required" then Error::Forbidden.new
        else Error.new(error.message)
        end
      end
    end

    private

    # The person as they stand now, as Invocation#admit_person! reloads them.
    def refresh_caller
      fresh = User.active.find_by(id: current_user.id) or raise Error::Forbidden
      current_caller.with(user: fresh)
    end

    # Current, the CRM change source and PaperTrail for the person, as
    # Invocation sets them for Base's actions.
    def within_request(&) = Invocation.within_request(person: current_user, service: nil, surface: current_caller.surface.to_sym,
      credential: current_caller.connection, &)

    # What a connection changed, once it has committed.
    def record_activity = ::Agents::Activity.record_change!(current_caller.connection, self.class, result.body)

    # The connection's areas stop short: the refusal is kept and the person
    # asked, with Base's AreaNotAllowed error.
    def refuse_area(error) = raise(Invocation.area_refusal(current_caller.connection, error.action))

    # As Base#authorize!: a refusal on a record is Error::Hidden, which the
    # run endpoint and /mcp answer as a missing record.
    def authorize!(record = :__undef__, **options)
      super
    rescue ActionPolicy::Unauthorized
      raise unless record.is_a?(ActiveRecord::Base)
      raise Error::Hidden
    end
  end
end
```

</details>

## 7. What breaks

Each removal fails loudly at boot or at the first call. There are no
compatibility shims and no deprecation warnings.

| Change | What fails | The fix |
|---|---|---|
| The 17 block settings are gone | `NoMethodError` from the initializer at boot | Move each one as section 2 says |
| `max_array_items` takes a number only | `ArgumentError` at boot | Set the number |
| `approvals` refuses `message:` and `current_tenant:` | `ArgumentError` at boot, as for any unknown key today | The I18n key; `:acts_as_tenant` |
| `Adapters::Audit::PaperTrail.request` is gone | `NoMethodError` in the hook that called it | `info_for_paper_trail` |
| The action is built before its input is checked | An action whose own `initialize` reads `params` would read none. Neither Unio nor Outport has one. | Read input in `perform` |
| `OutsideAccess` and `ForbiddenFields` are new subclasses | Nothing: clients see the same codes and statuses, and rescuing `InsufficientScope` or `Forbidden` still catches them | |
| `Caller#surface` is an `ActiveSupport::StringInquirer` (`activesupport-8.1.4/lib/active_support/string_inquirer.rb:21`), as `Rails.env` is | Nothing: comparing it with a string still works | `surface.assistant?` reads better |
| `changes.saltbox_actions` gains `invocation_id` | Nothing | |

**The safety properties**, each kept by a named piece of 1.3:

| Property | 1.2 | 1.3 |
|---|---|---|
| A revoked token or closed connection stops the next call, list and search | `refresh_caller` hook | `refresh_caller`, called first in every invocation, list and search. Unlike 1.2's default, which passed any caller through, the gem's default refuses a credential caller the app did not override. |
| A deactivated account, or one without staff-app access, stops | `refresh_caller` hook | `refresh_caller` |
| The chat needs its permission and the union's flag on every call, not only when the chat opens | `check_caller` | `before_invocation :require_assistant_chat`, which runs for every call, list and search |
| Every query is held to the caller's union, strictly | `org.with_tenant` and `TenantStrictness.enforce` in `around_invocation` | `:acts_as_tenant` sets the union; `act_as_account` keeps `TenantStrictness.enforce` |
| Reads skip the query cache | `uncached` in both hooks | `uncached` in `refresh_caller` and `act_as_account` |
| A refused connection call is recorded, in its union, and the person asked | `on_access_refused`, inside the set-up | `rescue_from Error::OutsideAccess`, whose handler runs inside the invocation callbacks (section 3, step 7) |
| Approvals are kept per union | `approvals` `tenant: "Org"`, with acts_as_tenant's tenant | the same setting, with the tenant `:acts_as_tenant` sets |
| A domain refusal keeps its code and status | `map_error` | `rescue_from Unio::Errors::BaseError` |
| A change and its event save together, or neither does | `on_changes` inside the transaction | the subscriber runs inside the transaction, and its exception rolls the change back |
| A connection's activity is written only once the change commits | `after_change_commit` | `after_commit`, never on rollback |
| An action's feature key is one Unio knows | at class load, in every environment | in the registry spec, in CI |

The last row is the one real difference: a mistyped key now fails CI instead
of failing at boot.

## 8. Order of work

Each step is a pull request, and each waits for Steve's go.

1. **saltbox-actions 1.3.0**, one PR:
   - Base: the invocation, perform and commit callbacks; Rescuable, with the
     gem's translations as `rescue_from` lines; `refresh_caller` and the gem's
     first invocation callback, which applies it; `current_tenant`,
     `self.permissions_held`, `self.with_schema_user` and `invocation_id`;
     input assigned after it is checked.
   - Invocation in section 3's order. `translate` and the error mappings go.
     `Saltbox::Actions.within` runs the base instance's invocation callbacks.
   - `Caller#surface` becomes a StringInquirer.
   - `Error::OutsideAccess` and `Error::ForbiddenFields`, worded with I18n.
     `Forbidden.for_fields` goes.
   - New adapters `:acts_as_tenant`, `:flipper` and `:pagy`. `:paper_trail`
     reads the action's methods, and the authorization adapters declare their
     `rescue_from`.
   - `approvals` gains `name:` and `url:` and loses `message:` and
     `current_tenant:`. The notification payload gains `invocation_id`.
   - Configuration loses the 17 block settings. `max_array_items` takes a
     number.
   - The install generator's template, a generator spec that boots section 4's
     app, the README sections each change touches (with the notification and its payload, which the README does not yet describe), the spec app (settings-only
     initializer; its ApplicationAction takes its hooks; acts_as_tenant for its
     approvals), the specs that set hooks (`within_spec`, `invocation_spec`,
     `areas_spec`, `check_task_spec`, `registry_spec`), and the CHANGELOG, with
     one line per removal and its replacement.
   - Release v1.3.0 once merged.
2. **Unio #1590** (branch `ft149-on-gem`): pin v1.3.0; replace the initializer
   and ApplicationAction with section 5's; add the subscriber, its subscription
   line, the locale lines and the registry spec example; shorten
   `TabularContent::ActionAdapter`; run `rails actions:dump` and commit the
   catalog, where five summary fields now come before the computed ones; run
   the specs those files touch.
3. **Outport OUT-1200** (#1383, on hold): pin v1.3.0 in place of v1.2.0, use
   section 6's initializer and ApplicationAction, and run its action specs.

## 9. Names for Steve to decide

These become the gem's public API. Each line gives the recommendation, with
alternatives where there is a real choice:

- **Callbacks** `before_invocation`, `around_invocation`, `after_invocation`.
  1.2's `around_invocation` already wraps a call, a list and a search.
  Alternatives: `*_call`, `*_request`.
- **Callbacks** `before_perform`, `around_perform`, `after_perform`,
  `after_commit`: Active Job's and Active Record's names.
- **Methods** `refresh_caller` (1.2's setting name), `current_tenant`
  (acts_as_tenant's), `user_for_paper_trail` and `info_for_paper_trail`
  (PaperTrail's), `invocation_id`.
- **Class methods** `self.permissions_held(caller)` (1.2's name) and
  `self.with_schema_user` (a yielding `with_*`, from 1.2's `schema_user`).
- **Errors** `Error::OutsideAccess` (alternative: `Error::AreaNotAllowed`,
  which Outport already uses for its own error) and `Error::ForbiddenFields`.
- **I18n keys** `actions.errors.forbidden_fields`,
  `actions.errors.forbidden_field` and `actions.errors.approval_needed`, beside
  the existing `actions.errors.not_in_lookup_list`.
- **`approvals` keys** `name:` and `url:`.
- **Adapters** `:acts_as_tenant`, `:flipper` and `:pagy`, named after their
  gems as `:pundit` and `:paper_trail` are.

## What was tested

- Building an instance of the app's base class from a caller and empty input
  works on gem 1.2. A one-off spec in the gem's dummy app built
  `ApplicationAction` this way and ran without error.
- ActiveSupport::Callbacks order on activesupport 8.1.4, in a script:
  - a parent class's callbacks run before a subclass's;
  - a `before` callback declared after an `around` runs inside it;
  - a `rescue_from` handler that raises leaves its new error with the original
    as its `cause`.
- Each fact cited from Rails, Pundit, PaperTrail, acts_as_tenant, Flipper, Pagy
  and Devise was read at the file and line given, in the installed gem (Devise
  5.0.4 was unpacked to read it).
- Every 1.3 file in sections 4 to 6 passes `ruby -c`, and the locale lines
  parse as YAML.
- Not tested: everything that needs gem 1.3. None of the after-files has run,
  and no Unio or Outport spec has run against them. The tests are gem 1.3's
  own specs and generator spec, then each app's specs, as section 8 lists.
