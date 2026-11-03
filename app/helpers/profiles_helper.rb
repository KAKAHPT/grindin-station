# frozen_string_literal: true

module ProfilesHelper
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

  # "3rd of 32" / "3.º de 32"; "–" without a final position.
  def profile_position(row)
    return "–" if row.position.nil?

    t("profiles.position", ordinal: row.position.ordinalize, position: row.position, total: row.participants)
  end

  # The decklist as a link when it is a web address, else as text.
  def decklist_link(url)
    return url unless url.match?(%r{\Ahttps?://}i)

    link_to url.sub(%r{\Ahttps?://}i, "").truncate(40), url, target: "_blank", rel: "noopener nofollow",
                                                             class: "text-accent hover:underline"
  end
end
