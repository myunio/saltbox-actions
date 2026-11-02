class Events::ShowNotesAction < ApplicationAction
  connections :never
  policy_rule :view_notes?

  def perform
    render :show, with_notes: true
  end
end
