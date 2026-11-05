# frozen_string_literal: true

# A request a `rate_limit` refuses is audited (the `with:` lambdas stay as they are), at most one row per ip and
# controller#action per minute, so a flood writes one row. Only the route and path are kept, never the
# parameters. Actions open to visitors never resume the session, so the actor comes from the session cookie
# when Current has none. (The test cache is a :null_store, where `unless_exist` always writes: no dedupe there.)
ActiveSupport::Notifications.subscribe("rate_limit.action_controller") do |*, payload|
  request = payload[:request]
  controller = request.path_parameters[:controller].to_s
  action = request.path_parameters[:action].to_s
  first_this_minute = Rails.cache.write("audit:rate_limited:#{request.remote_ip}:#{controller}##{action}", true,
                                        unless_exist: true, expires_in: 1.minute)
  next unless first_this_minute

  actor = Current.user || Session.find_by(id: request.cookie_jar.signed[:session_id])&.user
  Audit.record(:rate_limited, actor: actor, controller: controller, action: action, path: request.path)
end
