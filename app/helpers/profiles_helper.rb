# frozen_string_literal: true

module ProfilesHelper
  PROFILE_TAG = "inline-flex items-center px-1.5 border border-line-strong rounded text-muted uppercase " \
                "text-[10px] font-semibold tracking-[0.06em] leading-4"

  # The name linked to the profile when an anonymous visitor could open it (public), else plain text.
  def profile_link(user, label = user&.display_name)
    return label unless user&.handle.present? && user.profile_visible_to?(nil)

    link_to label, profile_path(user.handle, locale: params[:locale]), class: "hover:text-accent hover:underline"
  end

  # "Portugal" for "PT"; the code itself for countries without a name here.
  def country_name(code)
    t("profiles.countries.#{code}", default: code)
  end

  # "RG" for "Rita Grind".
  def profile_initials(user)
    user.display_name.split.first(2).pluck(0).join.upcase
  end

  # "3rd" in bold ink and " of 32" muted ("3.º de 32" in pt); "–" without a final position.
  def profile_position(row)
    return "–" if row.position.nil?

    rank = t("profiles.rank", ordinal: row.position.ordinalize, position: row.position)
    safe_join([tag.b(rank, class: "font-display font-bold text-ink"),
               tag.span(t("profiles.of_total", total: row.participants), class: "text-muted")], " ")
  end

  # "33%" for 33, "–" for nil (no games or no events).
  def profile_percent(value)
    value.nil? ? "–" : "#{value}%"
  end

  # Whole percent of part in whole, nil when whole is zero.
  def profile_share(part, whole)
    (part * 100.0 / whole).round unless whole.zero?
  end

  # Grey outlined "Top 4" after the event name when the player made the cut of a known size.
  def profile_cut_tag(row)
    return unless row.made_cut && row.cut_size

    tag.span(t("profiles.top_cut_tag", size: row.cut_size), class: PROFILE_TAG, data: { cut_tag: true })
  end

  # Grey outlined team tag after the name; nothing for a user without a team.
  def profile_team_tag(user)
    return if user.team.blank?

    tag.span(user.team, class: "#{PROFILE_TAG} shrink-0 truncate", data: { team: true })
  end

  # Years with events, newest first.
  def profile_years(rows)
    rows.map { |row| row.event.start_time.year }.uniq.sort.reverse
  end

  # Circuit names of the events, A-Z.
  def profile_seasons(rows)
    rows.filter_map(&:season).uniq.sort
  end

  # The decklist as a link when it is a web address, else as text.
  def decklist_link(url)
    return url unless url.match?(%r{\Ahttps?://}i)

    link_to url.sub(%r{\Ahttps?://}i, "").truncate(40), url, target: "_blank", rel: "noopener nofollow",
                                                             class: "text-ink underline-offset-2 hover:underline"
  end
end
