require "rake"

RSpec.describe "rails actions:check" do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("actions:check") }
  # The registry loads the action files itself; eager loading the whole
  # app here would hide a missing load from the other specs.
  before { allow(Rails.application).to receive(:eager_load!) }
  after { Saltbox::Actions::Registry.reset! }

  def check
    task = Rake::Task["actions:check"]
    task.reenable
    task.invoke
  end

  it "passes every action of the dummy app" do
    expect { check }.to output("All 10 actions pass.\n").to_stdout
  end

  it "fails naming the action and the fix for a policy without the action's rule" do
    allow(Event::CancelAction).to receive(:policy_query).and_return(:archive?)
    expect { expect { check }.to raise_error(SystemExit) }
      .to output(/Event::CancelAction: EventPolicy#archive\? is missing: add it, or authorize another query/).to_stderr
  end

  it "fails naming the action when its policy needs a person and no schema principal is set" do
    allow(Saltbox::Actions.config).to receive(:schema_principal).and_return(nil)
    expect { expect { check }.to raise_error(SystemExit) }
      .to output(/Event::CreateAction: building its input schema asked EventPolicy#permitted_attributes, which raised NoMethodError.*set config.schema_principal/).to_stderr
  end
end
