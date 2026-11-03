# frozen_string_literal: true

module ApplicationHelper
  RESULT_BASE = "inline-flex items-center font-medium"
  RESULT_CLASSES = {
    Advance => "#{RESULT_BASE} text-accent",
    Win => "#{RESULT_BASE} text-accent",
    Penalty => "#{RESULT_BASE} text-danger",
    Loss => "#{RESULT_BASE} text-muted",
    Eliminated => "#{RESULT_BASE} text-muted line-through",
    Draw => "#{RESULT_BASE} text-warn"
  }.freeze

  BUTTON_BASE = "inline-flex min-h-[52px] items-center justify-center gap-2 px-5 rounded-xl border " \
                "text-sm font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-accent/40"
  BUTTON_KINDS = {
    primary: "bg-accent text-ground border-accent hover:bg-accent/90",
    secondary: "bg-surface text-ink border-line hover:border-muted",
    danger: "bg-danger/10 text-danger border-danger/40 hover:bg-danger/20"
  }.freeze

  CHIP_TONES = {
    accent: "text-accent", muted: "text-muted", warn: "text-warn", danger: "text-danger", ink: "text-ink"
  }.freeze

  RESULT_ICONS = {
    Advance => "fast-forward",
    Win => "medal",
    Penalty => "gavel",
    Loss => "smiley-nervous",
    Eliminated => "smiley-x-eyes",
    Draw => "handshake"
  }.freeze

  def result_indicator(pod:, player:)
    result = pod.results.find { |r| r.event_participant_id == player.id }
    if result.instance_of?(Advance) && pod.present?
      tag.span(class: RESULT_CLASSES[Win]) do
        concat icon(pod.round.last_single_elimination_round? ? "trophy" : "medal", class: "me-2")
        concat truncate(player.name)
      end
    else
      result_badge(result, player)
    end
  end

  def result_badge(result, player)
    tag.span(class: RESULT_CLASSES[result.class]) do
      concat icon(RESULT_ICONS[result.class], class: "me-2")
      concat truncate(player.name)
    end
  end

  def badge(color:, &block)
    tag.span(class: %w[
      text-xs font-medium me-2 px-2.5 py-0.5 rounded
    ] + [
      "bg-#{color}-100", "text-#{color}-800",
      "dark:bg-#{color}-900", "dark:text-#{color}-300"
    ], &block)
  end

  # Palette A button: kind is :primary, :secondary or :danger; extra carries width/layout classes.
  def button_classes(kind = :secondary, extra = nil)
    [BUTTON_BASE, BUTTON_KINDS.fetch(kind), extra].compact.join(" ")
  end

  # Status chip: small dot plus uppercase label, coloured by tone (see CHIP_TONES).
  def status_chip(tone, data: nil, &block)
    tag.span(class: "inline-flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide " \
                    "#{CHIP_TONES.fetch(tone)}", data: data) do
      concat tag.span(class: "size-1.5 rounded-full bg-current", "aria-hidden": true)
      concat capture(&block)
    end
  end

  def icon(name, options = nil)
    css_classes = options&.dig(:class)
    tag.i(class: "ph-light ph-#{name} #{css_classes}")
  end

  def organizer_mode?
    url_for(controller: params[:controller], action: params[:action]).starts_with?("/organizer")
  end

  def organizer_path_builder
    path =
      params.dup.tap do |p|
        p[:controller] = organizer_mode? ? p[:controller].gsub("organizer", "") : "organizer/#{p[:controller]}"
      end

    url_for(path.permit!)
  rescue ActionController::UrlGenerationError
    url_for(organizer_mode? ? :tournaments : %i[organizer tournaments])
  end

  def modal_form_for(record, options = {}, &block)
    options[:builder] = ModalFormBuilder
    form_for(record, options, &block)
  end

  def current_player?(player)
    current_user&.player == player
  end
end
