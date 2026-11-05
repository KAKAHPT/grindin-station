# frozen_string_literal: true

# The M13 rankings world for the Board and /rankings tests: Ana and Bruno (PT, Porto Grinders), Carla (ES, Madrid Mana)
# and Diogo (ES, no team); organizers cEDH PT (the standard one, handle organizer-user) and Lisboa cEDH.
# This year (@this_year): Ana wins two cEDH pods of the four (cEDH PT), Carla beats Diogo at Legacy (1v1, Lisboa
# cEDH); last year (@last_year): Bruno wins a pod, Diogo beats Carla at Modern (1v1, Lisboa cEDH). Three play pools.
module RankingsFixture
  def build_rankings_world
    @last_year = (@this_year = Date.current.year) - 1
    @standard = event_organizers(:standard_organizer)
    @lisboa = new_user("Lisboa cEDH", handle: "lisboa-cedh").then(&:initialize_organizer)
    @ana, @bruno, @carla, @diogo = rankings_players
    rankings_events
    Rankings::Rebuild.call
  end

  def rankings_events
    four = [@ana, @bruno, @carla, @diogo]
    rankings_event(four, winner: @ana, organizer: @standard, year: @this_year)
    rankings_event(four, winner: @ana, organizer: @standard, year: @this_year)
    rankings_event([@carla, @diogo], winner: @carla, organizer: @lisboa, year: @this_year, game_format: "legacy")
    rankings_event(four, winner: @bruno, organizer: @standard, year: @last_year)
    rankings_event([@diogo, @carla], winner: @diogo, organizer: @lisboa, year: @last_year, game_format: "modern")
  end

  def rankings_players
    [new_user("Ana Carvalho", handle: "ana", country: "PT", team: "Porto Grinders"),
     new_user("Bruno Silva", handle: "bruno", country: "PT", team: "Porto Grinders"),
     new_user("Carla Costa", handle: "carla", country: "ES", team: "Madrid Mana"),
     new_user("Diogo Pereira", handle: "diogo", country: "ES")]
  end

  def new_user(name, handle: nil, country: nil, team: nil)
    User.create!(name: name, handle: handle, country: country, team: team, password: "password123",
                 email_address: "#{name.parameterize}-#{SecureRandom.hex(3)}@example.com")
  end

  # A finished one-round event of the users won by winner, who finishes first: one pod, or one 1v1 table of the
  # game_format when given.
  def rankings_event(users, winner:, organizer:, year:, game_format: nil)
    format = game_format ? "one_v_one" : "multiplayer"
    event = TournamentBuilder.build(players: users.size, organizer: organizer, state: :swiss, format: format)
    start = Time.zone.local(year, 6, 1)
    event.update_columns(swiss_rounds_count: 1, top_cut_size: 0, start_time: start, end_time: start + 1.day, # rubocop:disable Rails/SkipsModelValidations
                         game_format: game_format || event.game_format)
    seat_users(event, users, winner)
    play_rankings_round(event.rounds.create!(type: SwissRound, number: 1), winner, one_v_one: game_format.present?)
    event.update_column(:state, Tournament.states[:finished]) # rubocop:disable Rails/SkipsModelValidations
    event
  end

  def seat_users(event, users, winner)
    users.zip(event.event_participants.order(:created_at)) do |user, entry|
      entry.update_columns(player_id: user.player.id, final_position: (1 if user == winner)) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  # Win for the winner, Loss for the others (2-0 games in 1v1), then closes the round.
  def play_rankings_round(round, winner, one_v_one:)
    round.pods.sole.seatings.each do |seating|
      won = seating.event_participant.player_id == winner.player.id
      games = one_v_one ? one_v_one_games(won) : {}
      (won ? Win : Loss).create!(round: round, event_participant_id: seating.event_participant_id, **games)
    end
    round.update_columns(finished_at: Time.current, published: true) # rubocop:disable Rails/SkipsModelValidations
  end

  def one_v_one_games(won) = won ? { games_won: 2, games_lost: 0 } : { games_won: 0, games_lost: 2 }
end
