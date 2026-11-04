# frozen_string_literal: true

module RoundsHelper
  # Initial text of a round clock, so it is never blank before the JS takes over: mm:ss remaining ("00:00" when time
  # is up), or elapsed mm:ss for an untimed round (nil minutes).
  def clock_text(started_at, minutes)
    elapsed = (Time.current - started_at).floor
    seconds = minutes ? [(minutes * 60).to_i - elapsed, 0].max : [elapsed, 0].max
    minutes, secs = seconds.divmod(60)
    "#{minutes.to_s.rjust(2, '0')}:#{secs.to_s.rjust(2, '0')}"
  end
end
