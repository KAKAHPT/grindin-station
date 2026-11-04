# frozen_string_literal: true

# An external sign-in account (Google, Discord) linked to a user.
class Identity < ApplicationRecord
  belongs_to :user

  validates :provider, :uid, presence: true
  validates :uid, uniqueness: { scope: :provider }
end
