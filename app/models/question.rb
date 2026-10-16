class Question < ApplicationRecord
  enum :status, { pending: "pending", answered: "answered", failed: "failed" }, validate: true

  validates :text, presence: true
end
