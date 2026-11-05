# frozen_string_literal: true

class Current < ActiveSupport::CurrentAttributes
  attribute :session, :ip_address, :request_id, :request_path
  delegate :user, to: :session, allow_nil: true
end
