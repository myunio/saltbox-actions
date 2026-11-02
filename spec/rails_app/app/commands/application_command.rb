# The dummy app's base command, authorized with Pundit, with two verbs of
# its own.
class ApplicationCommand < Saltbox::Actions::Command
  include Saltbox::Actions::Authorization::Pundit

  abstract!

  verb :postpone, :rename, kind: :change, on: :member, idempotent: true
  verb :archive, kind: :destructive, on: :member
end
