# frozen_string_literal: true

module Tournaments
  # A supported top cut: how many players make it and, per elimination stage, how many of them
  # skip that stage (byes, the top seeds) and how many pods are played.
  TopCut =
    Data.define(:players, :stages) do
      def self.for(size, format: "multiplayer")
        stages = stages_for(size, format) || raise(ArgumentError, "unsupported top cut size: #{size.inspect}")
        new(players: size, stages: stages)
      end

      def self.sizes_for(format) = format == "one_v_one" ? self::ONE_V_ONE_SIZES : self::SIZES

      def self.rounds_for(size, format: "multiplayer") = self.for(size, format: format).rounds

      def self.valid_for?(size, players:, format: "multiplayer")
        sizes_for(format).include?(size) && self.for(size, format: format).valid_for?(players)
      end

      # 1v1: no byes, a single table of 2 per pair, halving every round (log2(size) rounds).
      def self.stages_for(size, format)
        return self::STAGES[size] unless format == "one_v_one"
        return unless self::ONE_V_ONE_SIZES.include?(size)

        Array.new(Math.log2(size).to_i) { |round| { byes: 0, pods: size / (2**(round + 1)) } }
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
  TopCut::ONE_V_ONE_SIZES = [2, 4, 8, 16, 32].freeze
end
