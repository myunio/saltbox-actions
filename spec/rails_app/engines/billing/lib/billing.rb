# A dummy isolated engine that ships its own actions. Its initializer adds
# its action folder, the way an engine adds its view or locale paths.
module Billing
  class Engine < ::Rails::Engine
    isolate_namespace Billing

    initializer "billing.actions" do
      Saltbox::Actions.config.action_paths.add(root.join("app/actions"), namespace: "billing")
    end
  end
end
