# frozen_string_literal: true

module NotificationsHelper
  # The line for one notification, linked to where it is dealt with when there is such a page.
  def notification_line(notification)
    event = notification.subject.try(:event)
    text = t("notifications.kinds.#{notification.kind}", default: notification.kind.humanize,
                                                         **notification_words(notification.subject, event))
    path = notification_path_for(notification, event)
    path ? link_to(text, path, class: "hover:text-accent hover:underline") : text
  end

  private

  # What the texts may name: the event, the user or team behind the subject, and the round that was published.
  def notification_words(subject, event)
    { event: event&.name, name: subject.try(:user).try(:display_name), team: subject.try(:team).try(:name),
      round: (subject.display_name if subject.is_a?(Round)) }
  end

  # Judge call → the staff's Judge Center; contested result or published round → the player's table; mention → the
  # feed; team request, invitation or acceptance → the account's Team card.
  def notification_path_for(notification, event)
    locale = params[:locale]
    case notification.kind
    when "mentioned" then mention_path(locale)
    when /\Ateam_/ then account_path(locale: locale, anchor: "team")
    when "judge_call" then event && organizer_tournament_judge_calls_path(event, locale: locale)
    when "result_contested", "round_published" then event && play_me_path(event.slug, locale: locale)
    end
  end

  # The feed, or nothing while it is paused (config/features.yml).
  def mention_path(locale) = (feed_path(locale: locale) if Features.on?(:feed))
end
