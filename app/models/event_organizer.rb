# frozen_string_literal: true

class EventOrganizer < ApplicationRecord
  belongs_to :user, optional: true

  has_many :events, dependent: :destroy
  has_many :circuits, dependent: :destroy

  delegate :name, to: :user

  CURRENCIES = {
    euro: 0,
    dollar: 1
  }.freeze

  enum :default_currency, CURRENCIES

  # The About links, in display order; each is a full http(s) URL or blank.
  LINKS = %w[website instagram discord youtube twitch x].freeze
  LINK_LABELS = { "website" => "Website", "instagram" => "Instagram", "discord" => "Discord", "youtube" => "YouTube",
                  "twitch" => "Twitch", "x" => "X" }.freeze

  validates :description, length: { maximum: 2000 }
  validates :location, length: { maximum: 80 }
  validate :links_are_urls
  normalizes :links, with: lambda { |links|
    links.to_h.slice(*LINKS).transform_values { |url|
      url.to_s.strip
    }.compact_blank
  }

  # [[key, url]] of the links set, in LINKS order.
  def link_list = LINKS.filter_map { |key| [key, links[key]] if links[key].present? }

  private

  def links_are_urls
    links.each do |key, url|
      errors.add(:links, :invalid_url, label: LINK_LABELS.fetch(key, key)) unless http_url?(url)
    end
  end

  def http_url?(url)
    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end
end
