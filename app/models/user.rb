class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  # nil when a save doesn't change the password; has_secure_password requires one on create.
  validates :password, length: { minimum: 12 }, allow_nil: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
