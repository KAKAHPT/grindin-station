# frozen_string_literal: true

# The /admin pages: the sparkline and the compact audit details.
module AdminHelper
  # Inline SVG polyline of values (oldest first), scaled to the box; no axes. The stroke is the text colour.
  def sparkline(values, width: 120, height: 28)
    tag.svg(class: "sparkline text-accent", viewBox: "0 0 #{width} #{height}", preserveAspectRatio: "none",
            "aria-hidden": true) do
      tag.polyline(points: sparkline_points(values, width, height), fill: "none", stroke: "currentColor",
                   "stroke-width": 1.5, "vector-effect": "non-scaling-stroke")
    end
  end

  # "key: value, key: value" from an audit row's data.
  def audit_details(data)
    data.to_h.map { |key, value| "#{key}: #{value}" }.join(", ")
  end

  private

  def sparkline_points(values, width, height)
    step = values.size > 1 ? width.to_f / (values.size - 1) : 0
    sparkline_ys(values, height).each_with_index.map { |y, i| "#{(i * step).round(1)},#{y}" }.join(" ")
  end

  # SVG y of each value: 0 at the bottom (height), the largest at the top (0).
  def sparkline_ys(values, height)
    y_scale = height / [values.max.to_i, 1].max.to_f
    values.map { |value| (height - (value * y_scale)).round(1) }
  end
end
