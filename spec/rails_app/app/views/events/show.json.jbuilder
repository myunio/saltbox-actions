json.data do
  json.event do
    json.call(@event, :id, :title, :starts_on, :capacity, :status)
    json.notes @event.notes if local_assigns[:with_notes]
  end
end
