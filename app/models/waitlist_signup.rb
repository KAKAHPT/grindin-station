# frozen_string_literal: true

# Someone asking to organise while organising is by invitation. The e-mail is stored lower-case, once.
class WaitlistSignup < ApplicationRecord
  normalizes :name, with: ->(name) { name.squish }
  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :name, presence: true, length: { maximum: 100 }
  validates :email, presence: true, length: { maximum: 254 }, format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: { case_sensitive: false }
end
