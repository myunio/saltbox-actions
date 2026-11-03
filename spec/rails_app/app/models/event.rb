class Event < ApplicationRecord
  has_paper_trail

  belongs_to :parent, class_name: "Event", optional: true
  enum :status, {draft: "draft", published: "published", cancelled: "cancelled"}, validate: true

  validates :title, presence: true
end
