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

  RESULT_ICONS = {
    Advance => "fast-forward",
    Win => "medal",
    Penalty => "gavel",
    Loss => "smiley-nervous",
    Eliminated => "smiley-x-eyes",
    Draw => "handshake"
  }.freeze

  def result_indicator(pod:, player:)
    result = pod.current_results.find { |r| r.event_participant_id == player.id }
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

  # Phosphor light icon from the local sprite (app/assets/images/icons.svg), sized to the font like
  # the old icon font; a w-*/h-* class in options[:class] overrides the size.
  def icon(name, options = nil)
    css_classes = options&.dig(:class)
    tag.svg(tag.use(href: "#{asset_path('icons.svg')}##{name}"),
            class: "inline-block size-[1em] shrink-0 align-[-0.125em] #{css_classes}".strip,
            fill: "currentColor", "aria-hidden": "true")
  end

  # Links between modal-style pages stay inside the modal frame when the page is in it, else navigate normally.
  def modal_nav_data
    turbo_frame_request_id == "modal" ? { turbo_frame: "modal" } : {}
  end

  def organizer_mode?
    url_for(controller: params[:controller], action: params[:action]).starts_with?("/organizer")
  end

  def admin_mode?
    controller_path.start_with?("admin/")
  end

  # The Organizer mode / public toggle: the same route in the other namespace, built from the path parameters
  # only. The query string is never handed to url_for: keys such as host, protocol or script_name would steer
  # the link to another origin.
  def organizer_path_builder
    route = request.path_parameters.except(:controller, :action, :format).to_h.symbolize_keys
    route[:locale] = params[:locale] if params[:locale].present?
    target = organizer_mode? ? controller_path.delete_prefix("organizer/") : "organizer/#{controller_path}"
    url_for(route.merge(controller: "/#{target}", action: params[:action], only_path: true))
  rescue ActionController::UrlGenerationError
    url_for(organizer_mode? ? :tournaments : %i[organizer tournaments])
  end

  def modal_form_for(record, options = {}, &block)
    options[:builder] = ModalFormBuilder
    form_for(record, options, &block)
  end
end
