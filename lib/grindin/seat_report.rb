# frozen_string_literal: true

module Grindin
  # One block of the public seat-fairness report (grindin:seat_report): `per` swiss tournaments of 50-60 players
  # with `rounds` rounds, played for real through the production pairing (Tournaments::CreatePodsJob: points,
  # rematch repair, pods of three, seats by history) against the database, each inside a transaction that is
  # rolled back. Every table is also seated at random, the baseline. Per seating: the share of players whose seat
  # spread (max - min count over seats 1-4) is at most 1 (fair_rate), the share who never sat at seat 1
  # (never_first), the spread histogram 0/1/2/3+, the seat-1 count histogram, each seat's share of all chairs and
  # the worst player's counts over seats 1-4.
  class SeatReport
    SEATINGS = %w[fair random].freeze
    PLAYERS = (50..60)
    DRAW_RATE = 0.3

    # The `per` tournaments split over `workers` processes; each tournament's seed depends only on its index, so
    # the split does not change the tournaments. Returns one { "fair" => [[n1, n2, n3, n4], ...], "random" => ... }
    # per tournament (a player's times in seats 1-4).
    def self.in_processes(rounds:, per:, seed:, workers:)
      ActiveRecord::Base.connection_handler.clear_all_connections!
      shares = (0...per).group_by { |index| index % workers }.values
      readers = shares.map { |indexes| fork_worker(new(rounds: rounds, seed: seed), indexes) }
      readers.flat_map { |reader| JSON.parse(reader.read) }.tap { Process.waitall }
    end

    # A child process that runs its share and writes the result, as JSON, to the pipe whose read end is returned.
    def self.fork_worker(report, indexes)
      reader, writer = IO.pipe
      fork do
        reader.close
        writer.write(JSON.generate(report.run(indexes)))
        writer.close
        exit!(0) # rubocop:disable Rails/Exit -- a forked worker must not run the parent's at_exit hooks
      end
      writer.close
      reader
    end

    def self.summarize(rounds, runs)
      SEATINGS.index_with do |seating|
        tally = Tally.new(rounds)
        runs.each { |run| tally.add(run.fetch(seating)) }
        tally.to_h.merge(tournaments: runs.size)
      end
    end

    def initialize(rounds:, seed:)
      @rounds = rounds
      @seed = seed
    end

    def run(indexes) = indexes.map { |index| tournament(index) }

    private

    def tournament(index)
      rng = Random.new(Digest::SHA256.hexdigest("#{@seed}:#{@rounds}:#{index}")[0, 8].hex)
      counts = SEATINGS.index_with { Hash.new { |players, id| players[id] = Array.new(4, 0) } }
      ActiveRecord::Base.transaction do
        event = build_event(rng)
        (1..@rounds).each { |number| play_round(event, number, rng, counts) }
        raise ActiveRecord::Rollback
      end
      counts.transform_values(&:values)
    end

    def build_event(rng)
      tag = SecureRandom.hex(4)
      event = Tournament.create!(name: "Seat report #{tag}", event_organizer: organizer(tag), state: :draft,
                                 start_time: Time.current, end_time: 1.day.from_now, game_format: "commander")
      rng.rand(PLAYERS).times do |i|
        event.event_participants.create!(player_name: "Player #{i + 1}", accepted_terms: true,
                                         player_email: "player-#{i + 1}-#{tag}@example.com")
      end
      event.update_columns(state: :swiss, swiss_rounds_count: @rounds, top_cut_size: 0, seed: rng.rand(2**31)) # rubocop:disable Rails/SkipsModelValidations
      event.reload
    end

    def organizer(tag)
      user = User.create!(name: "Seat report", email_address: "seat-report-#{tag}@example.com",
                          password: SecureRandom.hex(8))
      EventOrganizer.create!(user: user)
    end

    # Pairs the round for real, counts each table's seats (as dealt, and drawn at random) and writes its result.
    def play_round(event, number, rng, counts)
      round = event.rounds.create!(type: SwissRound, number: number)
      round.pods.includes(:seatings).find_each do |pod|
        seated = pod.seatings.sort_by(&:order).map(&:event_participant_id)
        count_seats(counts, seated, seated.shuffle(random: rng))
        score(round, seated, rng)
      end
      round.update_columns(finished_at: Time.current, published: true) # rubocop:disable Rails/SkipsModelValidations
    end

    def count_seats(counts, dealt, drawn)
      dealt.each_with_index { |id, seat| counts["fair"][id][seat] += 1 }
      drawn.each_with_index { |id, seat| counts["random"][id][seat] += 1 }
    end

    # DRAW_RATE of the tables draw, the others have one random winner.
    def score(round, seated, rng)
      winner = rng.rand < DRAW_RATE ? nil : seated.sample(random: rng)
      seated.each do |id|
        result_class(winner, id).create!(round: round, event_participant_id: id)
      end
    end

    def result_class(winner, id)
      return Draw if winner.nil?

      id == winner ? Win : Loss
    end

    # Accumulates the per-player seat counts ([times in seat 1, 2, 3, 4]) of every tournament.
    class Tally
      def initialize(rounds)
        @rounds = rounds
        @players = 0
        @spreads = Hash.new(0)
        @first_counts = Hash.new(0)
        @seat_totals = Array.new(4, 0)
        @worst = nil
      end

      def add(players)
        players.each { |counts| add_player(counts) }
        worst = players.max_by { |counts| spread(counts) }
        @worst = worst if worst && (@worst.nil? || spread(worst) > spread(@worst))
      end

      def to_h
        { players: @players, fair_rate: pct(@spreads[0] + @spreads[1]), never_first: pct(@first_counts[0], 2),
          spread: (0..3).map { |k| pct(@spreads[k]) }, first_counts: first_counts, seat_share: seat_share,
          worst_example: @worst }
      end

      private

      def first_counts = (0..[@rounds, 4].min).map { |k| pct(@first_counts[k]) }

      def seat_share = @seat_totals.map { |total| (total * 100.0 / @seat_totals.sum).round(1) }

      def add_player(counts)
        @players += 1
        @spreads[[spread(counts), 3].min] += 1
        @first_counts[counts.first] += 1
        counts.each_with_index { |count, seat| @seat_totals[seat] += count }
      end

      def spread(counts) = counts.max - counts.min

      def pct(count, digits = 1) = (count * 100.0 / @players).round(digits)
    end
  end
end
