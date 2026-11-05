# frozen_string_literal: true

# Palette A building blocks shared by the tournament-day pages: buttons, chips, segmented controls, seat squares.
module PaletteHelper
  LABEL = "font-display text-[13px] font-semibold tracking-[0.01em]"

  # Button sizes: :md 48 px (default, player pages and toolbars on mobile), :sm 36 px (cards, dense toolbars),
  # :xs 30 px (event tickets).
  BUTTON_SIZES = {
    md: "h-12 px-5 text-[13px]",
    sm: "h-9 px-3 text-[12px]",
    xs: "h-[30px] px-2.5 text-[11.5px]"
  }.freeze
  # Material lives in the .btn-* component classes of application.css.
  BUTTON_BASE = "btn inline-flex items-center justify-center gap-2 rounded-md whitespace-nowrap " \
                "font-display font-semibold tracking-[0.01em]"
  BUTTON_KINDS = { primary: "btn-primary", secondary: "btn-secondary", light: "btn-light", danger: "btn-danger",
                   ghost: "btn-ghost" }.freeze

  # Icon-only action: 36 px square by default, :sm 32 px (card headers), :xs 28 px (table rows).
  ICON_BUTTON = "btn btn-ghost inline-flex shrink-0 items-center justify-center rounded-md"
  ICON_BUTTON_SIZES = { md: "size-9", sm: "size-8", xs: "size-7 text-[13px]" }.freeze

  # Segmented control (round tabs, roster filters).
  SEGMENT_TRACK = "inline-flex flex-wrap items-center gap-0.5 p-0.5 rounded-md bg-surface-raised border border-line"
  SEGMENT_ITEM = "inline-flex items-center gap-1.5 py-1 px-2.5 rounded-[4px] border border-transparent " \
                 "transition-colors font-display text-[12px] font-semibold tracking-[0.01em]"
  SEGMENT_ACTIVE = "segment-active"
  SEGMENT_IDLE = "text-muted hover:text-ink"

  # 28x28 seat number square (pod cards, player table list).
  SEAT_SQUARE = "inline-flex size-7 shrink-0 items-center justify-center rounded-[4px] bg-surface-raised " \
                "font-display text-sm font-semibold"
  # 22x22 variant for the compact pod cards.
  SEAT_SQUARE_SM = "inline-flex size-[22px] shrink-0 items-center justify-center rounded-[4px] bg-surface-raised " \
                   "font-display text-[11px] font-semibold"

  CHIP_TONES = {
    accent: "text-accent", muted: "text-muted", warn: "text-warn", danger: "text-danger", ink: "text-ink"
  }.freeze

  # Palette A button: kind is :primary, :secondary, :danger or :ghost; extra carries width/layout classes.
  def button_classes(kind = :secondary, extra = nil, size: :md)
    [BUTTON_BASE, BUTTON_SIZES.fetch(size), BUTTON_KINDS.fetch(kind), extra].compact.join(" ")
  end

  # 36 px button for toolbars, card headers and modal footers (same as button_classes(kind, size: :sm)).
  def small_button_classes(kind = :secondary)
    button_classes(kind, size: :sm)
  end

  # Icon-only row action; danger ones turn red on hover. The label goes in title + sr-only text.
  def icon_button_classes(danger: false, size: :md)
    [ICON_BUTTON, ICON_BUTTON_SIZES.fetch(size), ("btn-ghost-danger" if danger)].compact.join(" ")
  end

  def segment_classes(active)
    "#{SEGMENT_ITEM} #{active ? SEGMENT_ACTIVE : SEGMENT_IDLE}"
  end

  # Route tab of shared/_tabs (underline teal when active).
  def tab_classes(active)
    active ? "tab tab-on" : "tab"
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
