# frozen_string_literal: true

module RoundsHelper
  # Initial text of a round clock, so it is never blank before the JS takes over: mm:ss remaining of the round's
  # length in seconds ("00:00" when time is up), or elapsed mm:ss for an untimed round (nil seconds).
  def clock_text(started_at, seconds)
    elapsed = (Time.current - started_at).floor
    shown = seconds ? [seconds.to_i - elapsed, 0].max : [elapsed, 0].max
    minutes, secs = shown.divmod(60)
    "#{minutes.to_s.rjust(2, '0')}:#{secs.to_s.rjust(2, '0')}"
  end

  # How long a closed round took, as m:ss (the organizer clock once the round is closed).
  def finished_clock_text(started_at, finished_at)
    minutes, secs = (finished_at - started_at).floor.divmod(60)
    "#{minutes}:#{secs.to_s.rjust(2, '0')}"
  end
end
