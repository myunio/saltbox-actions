require "json_schemer"

# Shared examples generic over any app. Each says what the including spec
# defines.

# The refusal ladder, by surface. The including spec defines:
# - `permitted_account`: a person whose role allows the action;
# - `arguments`: input that succeeds for the permitted person;
# - `unpermitted_account`, only when some people may not run it at all: a
#   person whose role does not allow it.
#
# Checked: the person without rights, when defined, is refused; each agent surface is
# refused or let through as the action's `connections` says; a read-only
# token cannot change; a browser assistant never runs a destructive action.
# With Configuration#enforce_confirm on, an agent's :confirm call is refused
# until the app's confirm hook approves it.
#
# @example
#   it_behaves_like "refuses callers the action does not allow" do
#     let(:arguments) { {id: event.id, title: "AGM"} }
#   end
RSpec.shared_examples "refuses callers the action does not allow" do
  if method_defined?(:unpermitted_account)
    it "refuses a person without its rights" do
      expect { run(arguments, as: as_screen(unpermitted_account)) }.to be_refused.with(:forbidden)
    end
  end

  it "lets the person run it on a screen" do
    expect { run(arguments, as: as_screen(permitted_account)) }.not_to be_refused
  end

  {mcp: :as_mcp, api: :as_api, assistant: :as_assistant, webmcp: :as_webmcp}.each do |surface, helper|
    it "answers #{surface} as its connections declaration says" do
      allowed = case described_class.connections
      when :allowed then !(surface == :webmcp && described_class.kind == :destructive)
      when :confirm then surface != :assistant && !(surface == :webmcp && described_class.kind == :destructive)
      else false
      end
      caller = public_send(helper, permitted_account)
      if allowed && described_class.connections == :confirm && Saltbox::Actions.config.enforce_confirm
        allow(Saltbox::Actions.config).to receive(:confirm).and_return(->(*) { false })
        expect { run(arguments, as: caller) }.to be_refused.with(:confirmation_required)
        allow(Saltbox::Actions.config).to receive(:confirm).and_return(->(*) { true })
      end
      outcome = expect { run(arguments, as: caller) }
      allowed ? outcome.not_to(be_refused) : outcome.to(be_refused.with(:human_required))
    end
  end

  # A read runs on a read-only token, and agents never run a :never action.
  if described_class.kind != :read && described_class.connections != :never
    it "needs a token that may change" do
      expect { run(arguments, as: as_read_only(permitted_account)) }.to be_refused.with(:insufficient_scope)
    end
  end
end

# For an action that works on one record. The including spec defines
# `permitted_account` and `hidden_arguments`: input that names a record the
# person may not see, such as another tenant's.
RSpec.shared_examples "hides records the caller cannot see" do
  it "answers a record the person cannot see as not found" do
    expect { run(hidden_arguments, as: as_screen(permitted_account)) }.to be_not_found
  end
end

# For an action that declares `returns`. The including spec defines
# `permitted_account` and `arguments`.
RSpec.shared_examples "renders its declared output schema" do
  it "renders a body that matches its output schema" do
    expect(run(arguments, as: as_screen(permitted_account))).to match_output_schema
  end
end

# The registry lint, included in one spec of the app's:
#
#   RSpec.describe "Actions" do
#     it_behaves_like "a valid action registry"
#   end
#
# Every action loads and passes the boot checks, has a spec file beside the
# others, compiles its input schema, and the committed catalogue matches the
# code (rewrite it with `bin/rails actions:catalogue`).
RSpec.shared_examples "a valid action registry" do
  let(:registry) { Saltbox::Actions::Registry }

  it "loads every action and passes the boot checks" do
    expect(registry.actions).not_to be_empty
  end

  it "has a spec file for every action" do
    paths = Saltbox::Actions.config.action_paths
    spec_root = Saltbox::Actions::RSpec.config.spec_root
    # Where the action folders hold other files too, each action's own file.
    files = Saltbox::Actions.config.every_file_an_action ? registry.action_files : registry.actions.map { registry.source(it) }
    # An engine's action spec may live in the app's spec folder or in the
    # engine's own: engines/billing/spec/actions beside engines/billing/app/actions.
    missing = files.map { |file| [file, paths.relative(file).sub_ext("_spec.rb")] }
      .reject { |file, spec| [spec_root, paths.for(file).root.join("../../spec/actions")].any? { it.join(spec).exist? } }
      .map(&:last)
    expect(missing.map(&:to_s)).to be_empty, "write #{missing.join(", ")} under #{spec_root}"
  end

  it "compiles every input schema" do
    invalid = registry.actions.reject { JSONSchemer.valid_schema?(it.input_schema) }
    expect(invalid.map(&:action_name)).to be_empty
  end

  it "matches the committed catalogue" do
    path = registry.catalogue_path
    expect(path).to exist, "write it with bin/rails actions:catalogue"
    expect(path.read).to eq(registry.catalogue_json), "the catalogue is out of date: run bin/rails actions:catalogue"
  end
end
