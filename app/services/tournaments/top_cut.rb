# frozen_string_literal: true

module Tournaments
  # A supported top cut: how many players make it and, per elimination stage, how many of them
  # skip that stage (byes, the top seeds) and how many pods are played.
  TopCut = Data.define(:players, :stages) do
    def self.for(size)
      stages = self::STAGES.fetch(size) { raise ArgumentError, "unsupported top cut size: #{size.inspect}" }
      new(players: size, stages: stages)
    end

    def rounds
      stages.size
    end

    def valid_for?(player_count)
      player_count >= players
    end
  end

  TopCut::STAGES = {
    4 => [{ byes: 0, pods: 1 }],
    10 => [{ byes: 2, pods: 2 }, { byes: 0, pods: 1 }],
    13 => [{ byes: 1, pods: 3 }, { byes: 0, pods: 1 }],
    16 => [{ byes: 0, pods: 4 }, { byes: 0, pods: 1 }],
    40 => [{ byes: 8, pods: 8 }, { byes: 0, pods: 4 }, { byes: 0, pods: 1 }]
  }.freeze
  TopCut::SIZES = TopCut::STAGES.keys.freeze
end
