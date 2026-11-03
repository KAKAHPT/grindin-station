# frozen_string_literal: true

# A generic in-app notice for one user (judge call, result pending, round published, ...).
class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :subject, polymorphic: true, optional: true

  scope :unread, -> { where(read_at: nil) }

  validates :kind, presence: true
end
