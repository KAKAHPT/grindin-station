# frozen_string_literal: true

class ModalFormBuilder < ActionView::Helpers::FormBuilder
  # The Settings look (see .field* in application.css): muted 12 px labels over dark inputs.
  FIELD_CLASSES = {
    "check_box" => "field-check",
    "default" => "field-input"
  }.freeze
  LABEL_CLASSES = "inline-flex items-center gap-2 text-[12px] text-muted"
  REQUIRED_BADGE_CLASSES = "text-[10.5px] font-semibold uppercase tracking-wide text-muted/70"
  WRAPPER_CLASSES = "field mb-4"

  def method_missing(method_name, *args, &block)
    return super unless method_name.to_s.end_with?("_with_label")

    original_method = method_name.to_s.chomp("_with_label")
    return super unless respond_to?(original_method)

    name, *rest = args
    options = rest.extract_options!
    required = !options[:required].nil?
    label_options = options[:label] || {}
    label_html =
      label(name, { class: LABEL_CLASSES }.merge(label_options.except(:text))) do |translation|
        @template.safe_join(
          [
            @template.content_tag(:span, label_options[:text] || translation),
            required ? @template.content_tag(:span, @template.t("helpers.required"), class: REQUIRED_BADGE_CLASSES) : nil
          ].compact
        )
      end
    field_html = public_send(
      original_method, name,
      *(rest + [{ class: "#{FIELD_CLASSES.fetch(original_method, FIELD_CLASSES['default'])} #{options[:class]}" }.merge(options.except(:class, :label))]), &block
    )

    @template.content_tag(:div, class: WRAPPER_CLASSES) do
      @template.safe_join([label_html, field_html])
    end
  end

  def select(method, choices = nil, options = {}, html_options = {}, &block)
    @template.select(
      @object_name, method, choices, objectify_options(options),
      @default_html_options.merge(class: FIELD_CLASSES["default"]).merge(html_options), &block
    )
  end

  def check_box_with_label(method, options = {}, checked_value = "1", unchecked_value = "0")
    label_html = label(
      method,
      options.dig(:label, :text),
      { class: "#{LABEL_CLASSES} ms-2 text-ink/90" }.merge(options[:label] || {})
    )
    check_box_html = check_box(
      method,
      objectify_options({ class: FIELD_CLASSES["check_box"] }.merge(options)),
      checked_value, unchecked_value
    )
    @template.content_tag(:div, class: "flex items-start mb-4") do
      @template.safe_join(
        [
          @template.content_tag(:div, class: "flex items-center h-5") { check_box_html },
          label_html
        ]
      )
    end
  end

  def submit(value = nil, options = {})
    if value.is_a?(Hash)
      options = value
      value = nil
    end
    value ||= submit_default_value
    @template.button_tag(
      value,
      {
        form: @options.dig(:html, :id),
        class: @template.button_classes(:primary, size: :xs)
      }.merge(options)
    )
  end

  def respond_to_missing?(method_name, include_private = false)
    method_name.to_s.end_with?("_with_label") || super
  end
end
