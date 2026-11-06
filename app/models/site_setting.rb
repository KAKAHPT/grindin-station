# frozen_string_literal: true

# A site-wide switch or value the admins set (key/value, strings). `SiteSetting.on?("feed_paused")`.
class SiteSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.get(key) = find_by(key: key)&.value

  def self.set(key, value)
    find_or_initialize_by(key: key).update!(value: value&.to_s)
  end

  def self.on?(key) = get(key) == "true"
end
