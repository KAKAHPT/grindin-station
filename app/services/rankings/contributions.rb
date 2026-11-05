# frozen_string_literal: true

module Rankings
  # The ranking_contributions rows of one event, as attribute hashes (one per non-waitlisted participant with a
  # player), from the event's current results. A fixed number of queries whatever the field.
  class Contributions
    def self.build(event) = new(event).build

    def initialize(event)
      @event = event
      @league = event.is_a?(League)
    end

    def build
      entries = @event.event_participants.where(waitlisted: false).preload(results: :round, player: :user).to_a
      field = entries.size
      players = entries.select(&:player_id)
      cut = @league ? Set.new : cut_ids(players)
      players.map { |participant| row(participant, field, cut.include?(participant.id)) }
    end

    private

    # Participants seated in a single-elimination pod, or advanced through a cut round without one
    # (as Profiles::History).
    def cut_ids(participants)
      cut = { rounds: { type: "SingleEliminationRound", event_id: @event.id } }
      seated = Seating.joins(pod: :round).where(cut).select(:event_participant_id)
      advanced = Advance.current.joins(:round).where(cut).select(:event_participant_id)
      EventParticipant.where(id: participants.map(&:id))
        .where(id: seated).or(EventParticipant.where(id: advanced)).pluck(:id).to_set
    end

    def row(participant, field, made_cut)
      games = swiss_games(participant)
      flags = flags(participant, made_cut)
      points = Points.total(field: field, **games.except(:losses), **flags, league: @league)
      base_attributes(participant, field).merge(games, flags, points: points, invitational_points: invitational(points))
    end

    # Per-game counts over Swiss rounds only (league play pods are Swiss rounds too); cut rounds count for
    # nothing per game in every format, the cut being rewarded by the bonuses (spec M13 D4). A bye is an
    # Advance in a Swiss round; Penalty is a Loss.
    def swiss_games(participant)
      swiss = participant.results.select { |result| result.round.is_a?(SwissRound) }
      { wins: swiss.count { |result| result.is_a?(Win) }, draws: swiss.count { |result| result.is_a?(Draw) },
        losses: swiss.count { |result| result.is_a?(Loss) }, byes: swiss.count { |result| result.is_a?(Advance) } }
    end

    def base_attributes(participant, field)
      user = participant.player.user
      { player_id: participant.player_id, event_id: @event.id, season: @event.start_time.year,
        country: user&.country, team: user&.team, event_organizer_id: @event.event_organizer_id,
        format: @event.play, field: field }
    end

    def flags(participant, made_cut)
      return { made_cut: false, top4: false, won: false } if @league

      # won with or without a cut; top4 only inside a cut.
      position = participant.final_position
      { made_cut: made_cut, top4: made_cut && position.present? && position.between?(1, 4), won: position == 1 }
    end

    def invitational(points)
      (points * BigDecimal(Event::TIER_MULTIPLIERS.fetch(@event.tier, 0).to_s)).round(2)
    end
  end
end
