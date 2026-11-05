# frozen_string_literal: true

module Organizer
  # Downloads for official reporting (EventLink invite list, Melee, TopDeck, records) and the printable results
  # sheet. Every download writes a data_exported audit row.
  class ExportsController < OrganizerController
    allow_roles :organizer, :scorekeeper, only: %i[players melee standings rounds pairings sheet]

    layout "print", only: :sheet

    before_action :load_event

    def players = send_csv("players", Exports::Players.call(@event))

    def melee = send_csv("melee", Exports::Melee.call(@event))

    def standings = send_csv("standings", Exports::Standings.call(@event))

    def rounds = send_csv("rounds", Exports::Rounds.call(@event))

    def pairings
      published = @event.rounds.published
      round = params.key?(:round) ? published.find_by!(number: params.expect(:round)) : published.order(:number).last!
      send_csv("pairings", Exports::Pairings.call(@event, round: round))
    end

    # Closed rounds only, so an ongoing event prints what is settled.
    def sheet
      @participants = Exports::CsvFile.participants(@event)
      @names = @event.event_participants.includes(player: :user).index_by(&:id)
      @rounds = @event.rounds.finished.order(:number).includes(:results, pods: :seatings)
      active, dropped = Feeds::Standings.ranked(@event).partition(&:playing?)
      @standings = active + dropped
      Audit.record("data_exported", event: @event, kind: "sheet")
    end

    private

    def load_event
      @event = Event.staffed_by(current_user).includes(event_organizer: :user).find(params.expect(:id))
    end

    def send_csv(kind, csv)
      Audit.record("data_exported", event: @event, kind: kind)
      send_data csv, type: "text/csv; charset=utf-8", filename: "#{@event.slug}-#{kind}.csv"
    end
  end
end
