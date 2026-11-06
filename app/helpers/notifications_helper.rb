# frozen_string_literal: true

module NotificationsHelper
  # The line for one notification, linked to where it is dealt with when there is such a page.
  def notification_line(notification)
    event = notification.subject.try(:event)
    text = t("notifications.kinds.#{notification.kind}", event: event&.name, default: notification.kind.humanize,
                                                         name: notification.subject.try(:user).try(:display_name))
    path = notification_path_for(notification, event)
    path ? link_to(text, path, class: "hover:text-accent hover:underline") : text
  end

  private

  # Judge call → the staff's Judge Center; contested result → the player's table.
  def notification_path_for(notification, event)
    return feed_path(locale: params[:locale]) if notification.kind == "mentioned"
    return unless event

    case notification.kind
    when "judge_call" then organizer_tournament_judge_calls_path(event, locale: params[:locale])
    when "result_contested" then play_me_path(event.slug, locale: params[:locale])
    end
  end
end
