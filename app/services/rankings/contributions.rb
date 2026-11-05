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
      games = { wins: participant.number_of_wins, draws: participant.number_of_draws,
                byes: participant.number_of_byes }
      flags = flags(participant, made_cut)
      points = Points.total(field: field, **games, **flags, league: @league)
      base_attributes(participant, field).merge(games, flags, losses: participant.number_of_losses, points: points,
                                                              invitational_points: invitational(points))
    end

    def base_attributes(participant, field)
      user = participant.player.user
      { player_id: participant.player_id, event_id: @event.id, season: @event.start_time.year,
        country: user&.country, team: user&.team, event_organizer_id: @event.event_organizer_id,
        format: @event[:format], field: field }
    end

    def flags(participant, made_cut)
      return { made_cut: false, top4: false, won: false } if @league

      position = participant.final_position
      { made_cut: made_cut, top4: position.present? && position.between?(1, 4), won: position == 1 }
    end

    def invitational(points)
      (points * BigDecimal(Event::TIER_MULTIPLIERS.fetch(@event.tier, 0).to_s)).round(2)
    end
  end
end
