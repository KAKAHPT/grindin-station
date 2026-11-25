# frozen_string_literal: true

module NotificationsHelper
  # The line for one notification, linked to where it is dealt with when there is such a page.
  def notification_line(notification)
    subject = notification.subject
    event = subject.is_a?(Event) ? subject : subject.try(:event)
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
  def notification_path_for(notification, event) # rubocop:disable Metrics/CyclomaticComplexity -- one line per kind
    locale = params[:locale]
    case notification.kind
    when "mentioned" then mention_path(locale)
    when /\Ateam_/ then account_path(locale: locale, anchor: "team")
    when /\Aleague_/ then league_notification_path(notification.kind, event, locale)
    when "judge_call" then event && judge_call_path_for(event, locale)
    when "result_contested", "round_published" then event && play_me_path(event.slug, locale: locale)
    end
  end

  # A league's contested result goes to the organizer's league page; a tournament's to its Judge Center.
  def judge_call_path_for(event, locale)
    return organizer_tournament_judge_calls_path(event, locale: locale) unless event.is_a?(League)

    organizer_league_path(event, locale: locale) if Features.on?(:leagues)
  end

  # Staff notices (a cancellation asked, a table stuck) lead to the organizer's league page; the players'
  # (table full, cancellation decided) to the league's Tables tab.
  def league_notification_path(kind, league, locale)
    return unless league && Features.on?(:leagues)

    staff = kind.in?(%w[league_cancel_requested league_table_stale])
    staff ? organizer_league_path(league, locale: locale) : league_path(league, tab: "mine", locale: locale)
  end

  # The feed, or nothing while it is paused (config/features.yml).
  def mention_path(locale) = (feed_path(locale: locale) if Features.on?(:feed))
end
