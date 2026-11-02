# The registry lint an app includes, in an app whose actions folder holds
# other files too (every_file_an_action off).
RSpec.describe "a valid action registry, beside other files" do
  around do |example|
    with_settings(every_file_an_action: false) do
      Saltbox::Actions::Registry.reset!
      example.run
    ensure
      Saltbox::Actions::Registry.reset!
    end
  end

  # As in a folder with schemas or helpers beside the actions.
  before { allow(Saltbox::Actions::Registry).to receive(:action_files).and_raise(ArgumentError, "not every file here is an action") }

  it_behaves_like "a valid action registry"
end
