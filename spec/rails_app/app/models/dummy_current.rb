# The request's tenant, which around_invocation sets from the caller.
class DummyCurrent < ActiveSupport::CurrentAttributes
  attribute :org
end
