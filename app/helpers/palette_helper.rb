# frozen_string_literal: true

# Palette A building blocks shared by the tournament-day pages: buttons, chips, segmented controls, seat squares.
module PaletteHelper
  BUTTON_BASE = "inline-flex min-h-[52px] items-center justify-center gap-2 px-5 rounded-xl border " \
                "text-sm font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-accent/40"
  BUTTON_KINDS = {
    primary: "bg-accent text-ground border-accent hover:bg-accent/90",
    secondary: "bg-surface text-ink border-line hover:bg-surface-raised hover:border-line-strong",
    danger: "bg-danger/10 text-danger border-danger/40 hover:bg-danger/20"
  }.freeze

  # Small row action (roster check in, paid, drop...): ghost button, 36 px.
  SMALL_BUTTON_BASE = "inline-flex h-9 items-center px-3 me-2 rounded-lg border text-sm font-semibold transition-colors"
  SMALL_BUTTON_KINDS = {
    primary: "bg-accent/10 text-accent border-accent/30 hover:bg-accent/20",
    secondary: "bg-transparent text-ink border-line hover:bg-surface-raised hover:border-line-strong",
    danger: "bg-transparent text-danger border-danger/30 hover:bg-danger/10"
  }.freeze

  # Segmented control (round tabs, roster filters).
  SEGMENT_TRACK = "inline-flex flex-wrap items-center gap-1 p-1 rounded-xl bg-surface-raised border border-line"
  SEGMENT_ITEM = "inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors"
  SEGMENT_ACTIVE = "bg-surface shadow-card text-ink"
  SEGMENT_IDLE = "text-muted hover:text-ink"

  # 28x28 seat number square (pod cards, player table list).
  SEAT_SQUARE = "inline-flex size-7 shrink-0 items-center justify-center rounded-md bg-surface-raised " \
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
