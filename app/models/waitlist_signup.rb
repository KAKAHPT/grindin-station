# frozen_string_literal: true

# Someone asking to organise while organising is by invitation. The e-mail is stored lower-case, once.
# An admin approves (needs an account with that e-mail) or declines it on /admin/organizers (M13 D17).
class WaitlistSignup < ApplicationRecord
  belongs_to :approved_by, class_name: "User", optional: true

  normalizes :name, with: ->(name) { name.squish }
  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :name, presence: true, length: { maximum: 100 }
  validates :email, presence: true, length: { maximum: 254 }, format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: { case_sensitive: false }

  scope :pending, -> { where(approved_at: nil, declined_at: nil) }
  scope :approved, -> { where.not(approved_at: nil) }
  scope :declined, -> { where.not(declined_at: nil) }

  # The account signed up with this e-mail, if any.
  def user = User.find_by(email_address: email)

  def pending? = approved_at.nil? && declined_at.nil?

  # The list passes the account it already loaded, so the rows cost no query each.
  def approvable?(account = user) = pending? && account.present?
end
