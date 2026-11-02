RSpec.describe Saltbox::Actions::Finder do
  let(:finder) { described_class.new(Saltbox::Actions::Registry.actions) }

  def found(request, among: finder) = among.find(request).map(&:action_name)

  it "ranks by title, name and description, matching other forms of a word and ignoring filler words" do
    expect(finder.find("removing events").first).to eq(Event::DeleteAction)
    expect(finder.find("the and of")).to be_empty
    expect(described_class.stem("boxes")).to eq("box")
    expect(described_class.stem("types")).to eq("type")
  end

  # Requests in people's own words and the action each should find first.
  {
    "say why the meeting was called off" => "cancel_event", "how many have a status" => "count_events",
    "newest first" => "list_events", "who acts for this connection" => "whoami",
    "change the date" => "update_event", "private notes" => "show_event_notes"
  }.each do |request, action|
    it "finds #{action} for \"#{request}\"" do
      expect(found(request).first).to eq(action)
    end
  end

  it "finds nothing for a request sharing one description word with several actions, rather than those actions" do
    expect(found("say hello")).to be_empty
    expect(found("send a newsletter")).to be_empty
  end

  it "finds the one action using a description word when nothing else matches" do
    expect(found("the capacity")).to eq(["update_event"])
  end

  # Descriptions written so each word's rarity is known: "ticket" and "venue"
  # are in three descriptions, the rest in two each, so none falls back as
  # the one action using a word.
  context "weighing description words" do
    let(:action) { Data.define(:action_name, :title, :description) }
    let(:weighed) do
      described_class.new([
        action.new("first", "First", "Handles ticket and venue questions."),
        action.new("second", "Second", "Handles ticket and venue changes."),
        action.new("third", "Third", "Handles ticket and venue moves."),
        action.new("fourth", "Fourth", "Handles refund and waitlist requests."),
        action.new("fifth", "Fifth", "Handles parking and catering."),
        action.new("sixth", "Sixth", "Handles refund and waitlist complaints."),
        action.new("seventh", "Seventh", "Handles parking and catering bookings.")
      ])
    end

    it "drops an action whose words carry less than half the weight of the request's known words" do
      expect(found("ticket venue refund waitlist", among: weighed)).to contain_exactly("fourth", "sixth")
    end

    it "keeps an action whose words carry half that weight or more" do
      expect(found("refund waitlist parking catering", among: weighed)).to contain_exactly("fourth", "fifth", "sixth", "seventh")
      expect(found("ticket venue refund", among: weighed)).to contain_exactly("first", "second", "third")
    end
  end

  it "ignores words no action uses, such as a person's name" do
    expect(found("say why Jane Smith called it off")).to eq(found("say why it was called off"))
  end

  # A small app's catalogue makes every word's rarity much the same; a match
  # in the description alone must still count there.
  context "with a five-action catalogue" do
    let(:five) { described_class.new([Event::ListAction, Event::CreateAction, Event::CancelAction, Reports::CountEventsAction, WhoamiAction]) }

    {
      "say why the meeting was called off" => "cancel_event", "how many have a status" => "count_events",
      "newest first" => "list_events", "who acts for this connection" => "whoami"
    }.each do |request, action|
      it "finds #{action} for \"#{request}\" from its description alone" do
        expect(found(request, among: five)).to eq([action])
      end
    end

    it "finds the one action using a description word, but nothing for a word several share" do
      expect(found("newest", among: five)).to eq(["list_events"])
      expect(found("say hello", among: five)).to be_empty
    end
  end

  it "searches only the actions it is given and returns no more than the number asked for" do
    expect(described_class.new([Event::ShowAction]).find("event")).to eq([Event::ShowAction])
    expect(finder.find("event", limit: 2).size).to eq(2)
  end
end
