# frozen_string_literal: true

# Every request a `rate_limit` refuses is audited once (the `with:` lambdas stay as they are). Only the route
# and path are kept, never the parameters. Actions open to visitors never resume the session, so the actor
# comes from the session cookie when Current has none.
ActiveSupport::Notifications.subscribe("rate_limit.action_controller") do |*, payload|
  request = payload[:request]
  actor = Current.user || Session.find_by(id: request.cookie_jar.signed[:session_id])&.user
  Audit.record(:rate_limited, actor: actor, controller: request.path_parameters[:controller].to_s,
                              action: request.path_parameters[:action].to_s, path: request.path)
end
