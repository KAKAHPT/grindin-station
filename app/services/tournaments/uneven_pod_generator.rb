# frozen_string_literal: true

module Tournaments
  # Pod sizes for a multiplayer swiss round. Pods of 4 first, pods of 3 last, never a pod of 5.
  # With r = count % 4: pods_of_three fills r = 1, 2, 3 with three, two, one pods of 3 (5 players: a pod of 4 and
  # a bye); byes keeps pods of 4 and gives r byes for r = 1, 2, and one pod of 3 for r = 3.
  class UnevenPodGenerator
    PREFERRED = Event::PREFERRED_POD_SIZE
    SMALLER = Event::SMALLER_POD_SIZE

    def self.shape(count, uneven_field)
      fours, rest = count.divmod(PREFERRED)
      return { sizes: [PREFERRED] * fours, byes: rest } if rest.between?(1, 2) && (uneven_field == "byes" || count == 5)

      smalls = rest.zero? ? 0 : PREFERRED - rest
      { sizes: ([PREFERRED] * ((count - (SMALLER * smalls)) / PREFERRED)) + ([SMALLER] * smalls), byes: 0 }
    end

    def initialize(round)
      @round = round
    end

    # Builds the round's pods for `count` seated-or-bye players; returns the shape.
    def generate_pods!(count)
      shape = self.class.shape(count, @round.event.uneven_field)
      shape[:sizes].each.with_index(1) { |size, number| @round.pods.build(number: number, size: size) }
      shape
    end
  end
end
