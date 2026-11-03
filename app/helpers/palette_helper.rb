# frozen_string_literal: true

# Palette A building blocks shared by the tournament-day pages: buttons, chips, segmented controls, seat squares.
module PaletteHelper
  LABEL = "font-display text-[13px] font-semibold tracking-[0.01em]"

  # Large button (48 px). Material lives in the .btn-* component classes of application.css.
  BUTTON_BASE = "btn inline-flex h-12 items-center justify-center gap-2 px-5 rounded-md whitespace-nowrap " \
                "#{LABEL}".freeze
  BUTTON_KINDS = { primary: "btn-primary", secondary: "btn-secondary", danger: "btn-danger" }.freeze

  # Small button (36 px): toolbars, card headers, modal footers.
  SMALL_BUTTON_BASE = "btn inline-flex h-9 items-center justify-center gap-1.5 px-3 rounded-md whitespace-nowrap " \
                      "#{LABEL}".freeze
  SMALL_BUTTON_KINDS = { primary: "btn-primary", secondary: "btn-secondary", danger: "btn-danger" }.freeze

  # Icon-only row action (36 px square).
  ICON_BUTTON = "btn btn-ghost inline-flex size-9 items-center justify-center rounded-md"

  # Segmented control (round tabs, roster filters).
  SEGMENT_TRACK = "inline-flex flex-wrap items-center gap-0.5 p-0.5 rounded-md bg-surface-raised border border-line"
  SEGMENT_ITEM = "inline-flex items-center gap-1.5 h-8 px-3 rounded-[4px] border border-transparent " \
                 "transition-colors #{LABEL}".freeze
  SEGMENT_ACTIVE = "segment-active"
  SEGMENT_IDLE = "text-muted hover:text-ink"

  # 28x28 seat number square (pod cards, player table list).
  SEAT_SQUARE = "inline-flex size-7 shrink-0 items-center justify-center rounded-[4px] bg-surface-raised " \
                "font-display text-sm font-semibold"

  CHIP_TONES = {
    accent: "text-accent", muted: "text-muted", warn: "text-warn", danger: "text-danger", ink: "text-ink"
  }.freeze

  # Palette A button: kind is :primary, :secondary or :danger; extra carries width/layout classes.
  def button_classes(kind = :secondary, extra = nil)
    [BUTTON_BASE, BUTTON_KINDS.fetch(kind), extra].compact.join(" ")
  end

  def small_button_classes(kind = :secondary)
    "#{SMALL_BUTTON_BASE} #{SMALL_BUTTON_KINDS.fetch(kind)}"
  end

  # Icon-only row action; danger ones turn red on hover. The label goes in title + sr-only text.
  def icon_button_classes(danger: false)
    danger ? "#{ICON_BUTTON} btn-ghost-danger" : ICON_BUTTON
  end

  def segment_classes(active)
    "#{SEGMENT_ITEM} #{active ? SEGMENT_ACTIVE : SEGMENT_IDLE}"
  end

  # Status chip: small dot plus uppercase label, coloured by tone (see CHIP_TONES).
  def status_chip(tone, data: nil, &block)
    tag.span(class: "inline-flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide " \
                    "#{CHIP_TONES.fetch(tone)}", data: data) do
      concat tag.span(class: "size-1.5 rounded-full bg-current", "aria-hidden": true)
      concat capture(&block)
    end
  end
end
