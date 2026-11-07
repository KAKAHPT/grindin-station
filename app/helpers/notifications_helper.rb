# frozen_string_literal: true

module NotificationsHelper
  # The line for one notification, linked to where it is dealt with when there is such a page.
  def notification_line(notification)
    event = notification.subject.try(:event)
    text = t("notifications.kinds.#{notification.kind}", event: event&.name, default: notification.kind.humanize,
                                                         name: notification.subject.try(:user).try(:display_name),
                                                         team: notification.subject.try(:team).try(:name))
    path = notification_path_for(notification, event)
    path ? link_to(text, path, class: "hover:text-accent hover:underline") : text
  end

  private

  # Judge call → the staff's Judge Center; contested result → the player's table; mention → the feed; team
  # request, invitation or acceptance → the account's Team card.
  def notification_path_for(notification, event)
    locale = params[:locale]
    case notification.kind
    when "mentioned" then feed_path(locale: locale)
    when /\Ateam_/ then account_path(locale: locale, anchor: "team")
    when "judge_call" then event && organizer_tournament_judge_calls_path(event, locale: locale)
    when "result_contested" then event && play_me_path(event.slug, locale: locale)
    end
  end
end
