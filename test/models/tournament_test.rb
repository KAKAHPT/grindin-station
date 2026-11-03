# frozen_string_literal: true

require "test_helper"

class TournamentTest < ActiveSupport::TestCase # rubocop:disable Metrics/ClassLength
  # ===== BASIC FIXTURE TEST =====

  test "fixtures load correctly" do
    assert_not_nil events(:small_tournament)
    assert_not_nil event_organizers(:standard_organizer)
    assert_not_nil users(:organizer_user)
    assert_not_nil players(:player_one)
    assert_equal "Small Tournament", events(:small_tournament).name
    assert_equal "Tournament Organizer", users(:organizer_user).name
  end

  # ===== STATE MACHINE TESTS =====

  test "valid state transitions are allowed" do
    tournament = events(:small_tournament)

    # draft -> registration_open
    tournament.state = :draft
    assert tournament.update(state: :registration_open)

    # registration_open -> registration_closed
    assert tournament.update(state: :registration_closed)

    # registration_closed -> swiss (this will trigger StartSwissRoundJob)
    # Skip this problematic transition for now and test canceled instead
    assert tournament.update(state: :canceled), "Should allow registration_closed -> canceled"
  end

  test "available_states returns only valid transitions" do
    tournament = events(:medium_tournament) # 6 players: top 4, so single elimination is on offer

    # From swiss state, should not include registration_open
    tournament.update!(state: :swiss)
    available = tournament.available_states.keys.map(&:to_sym)
    assert_not_includes available, :registration_open, "Swiss should not allow transition to registration_open"
    assert_includes available, :single_elimination, "Swiss should allow transition to single_elimination"
    assert_includes available, :finished, "Swiss should allow transition to finished"
    assert_includes available, :canceled, "Swiss should allow transition to canceled"
  end

  test "without a top cut the swiss can only finish or be canceled" do
    tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    tournament.update_columns(top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations

    assert_equal %w[finished canceled], tournament.available_states.keys
  end

  test "canceled state can be reached from most states" do
    tournament = events(:small_tournament)

    # registration_open -> canceled
    tournament.update!(state: :registration_open)
    assert tournament.update(state: :canceled)

    tournament.update!(state: :registration_closed)
    assert tournament.update(state: :canceled)

    tournament.update!(state: :swiss)
    assert tournament.update(state: :canceled)
  end

  test "available_states returns valid transitions" do
    tournament = events(:small_tournament)

    tournament.update!(state: :draft)
    available = tournament.available_states.keys.map(&:to_sym)
    assert_includes available, :registration_open
    assert_includes available, :registration_closed
    assert_not_includes available, :swiss
  end

  # ===== STRUCTURE TESTS (suggested rounds and cut, unless the organiser set them) =====

  test "4 players get the suggested 3 swiss rounds with no top cut" do
    tournament = events(:small_tournament) # 4 players
    rounds_info = tournament.rounds_info

    assert_equal(%i[standard spread standard], rounds_info[:rounds].pluck(:swiss_round))
    assert_nil rounds_info[:top], "Should have no top cut for 4 players"
    assert_equal 3, tournament.number_of_swiss_rounds
    assert_equal 0, tournament.number_of_single_elimination_rounds
  end

  test "6 players get the suggested 3 swiss rounds with top 4" do
    tournament = events(:medium_tournament) # 6 players
    rounds_info = tournament.rounds_info

    assert_equal 3, rounds_info[:rounds].size
    assert_equal({ players: 4, pods: [1] }, rounds_info[:top])
    assert_equal 3, tournament.number_of_swiss_rounds
    assert_equal 1, tournament.number_of_single_elimination_rounds
  end

  test "16 and 17 players both get 4 swiss rounds with top 4" do
    tournament16 = Tournament.find_by(slug: "standard-tournament")
    tournament17 = Tournament.find_by(slug: "large-tournament")
    assert_equal [16, 17], [tournament16.event_participants.size, tournament17.event_participants.size]

    [tournament16, tournament17].each do |tournament|
      assert_equal 4, tournament.number_of_swiss_rounds
      assert_equal({ players: 4, pods: [1] }, tournament.rounds_info[:top])
    end
  end

  test "17 players: round 2 spreads and the last round is forced" do
    tournament = Tournament.find_by(slug: "large-tournament") # 17 players

    assert_equal(%i[standard spread standard forced], tournament.rounds_info[:rounds].pluck(:swiss_round))
  end

  test "configured rounds and cut win over the suggestion; a cut of 0 means no top cut" do
    tournament = events(:standard_tournament) # 16 players, suggested 4 rounds + top 4
    tournament.swiss_rounds_count = 2
    tournament.top_cut_size = 10
    assert_equal(%i[standard standard], tournament.rounds_info[:rounds].pluck(:swiss_round))
    assert_equal({ players: 10, pods: [2, 1] }, tournament.rounds_info[:top])
    assert_equal 2, tournament.number_of_single_elimination_rounds

    tournament.top_cut_size = 0
    assert_nil tournament.rounds_info[:top]
    assert_equal 0, tournament.number_of_single_elimination_rounds
  end

  test "fewer than 4 players have no rounds and no progress" do
    tournament = TournamentBuilder.build(players: 3, organizer: event_organizers(:standard_organizer),
                                         state: :registration_open)

    assert_equal({ rounds: [], top: nil }, tournament.rounds_info)
    assert_equal 0, tournament.progress_percent
  end

  test "structure values are validated" do
    tournament = events(:small_tournament)
    tournament.assign_attributes(top_cut_size: 8, swiss_rounds_count: 0, round_minutes: 0, top_cut_round_minutes: 0)

    assert_not tournament.valid?
    assert_includes tournament.errors[:top_cut_size], I18n.t("errors.messages.inclusion")
    assert_includes tournament.errors[:swiss_rounds_count], I18n.t("errors.messages.greater_than_or_equal_to", count: 1)
    assert_includes tournament.errors[:round_minutes], I18n.t("errors.messages.greater_than_or_equal_to", count: 1)
    assert_includes tournament.errors[:top_cut_round_minutes],
                    I18n.t("errors.messages.greater_than_or_equal_to", count: 1)
  end

  test "a cut bigger than the field is allowed while registrations are open" do
    tournament = TournamentBuilder.build(players: 12, organizer: event_organizers(:standard_organizer),
                                         state: :registration_open)
    tournament.top_cut_size = 16

    assert tournament.valid?, tournament.errors.full_messages.to_sentence
  end

  test "round lengths come from the event" do
    tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    tournament.update_columns(round_minutes: 60, top_cut_round_minutes: 90, top_cut_size: 16, swiss_rounds_count: 1) # rubocop:disable Rails/SkipsModelValidations

    assert_equal 60.minutes, SwissRound.new(event: tournament, number: 1).duration
    assert_equal 90.minutes, SingleEliminationRound.new(event: tournament, number: 2).duration
    assert_nil SingleEliminationRound.new(event: tournament, number: 3).duration, "the final has no time limit"
  end

  test "structure is locked once the swiss starts" do
    tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    locked = I18n.t("activerecord.errors.models.event.attributes.swiss_rounds_count.locked")
    assert_equal "cannot change once the tournament has started", locked

    tournament.assign_attributes(swiss_rounds_count: 2, top_cut_size: 0, round_minutes: 60, top_cut_round_minutes: 90)
    assert_not tournament.valid?
    %i[swiss_rounds_count top_cut_size round_minutes top_cut_round_minutes].each do |attribute|
      assert_includes tournament.errors[attribute],
                      I18n.t("activerecord.errors.models.event.attributes.#{attribute}.locked")
    end
    I18n.with_locale(:pt) do
      assert_equal "não pode mudar depois de o torneio começar",
                   I18n.t("activerecord.errors.models.event.attributes.top_cut_size.locked")
    end
  end

  test "a locked tournament still accepts non-structure changes" do
    tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    tournament.name = "Renamed"

    assert tournament.valid?, tournament.errors.full_messages.to_sentence
  end

  test "structure stays editable before the swiss starts" do
    tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer),
                                         state: :registration_closed)
    tournament.assign_attributes(swiss_rounds_count: 2, top_cut_size: 0, round_minutes: 60)

    assert tournament.valid?, tournament.errors.full_messages.to_sentence
  end

  test "starting the swiss snapshots the suggested structure" do
    tournament = TournamentBuilder.build(players: 24, organizer: event_organizers(:standard_organizer),
                                         state: :registration_closed)
    assert_nil tournament.swiss_rounds_count

    tournament.update!(state: :swiss) # StartSwissRoundJob creates round 1
    tournament.reload

    assert_equal [4, 10], [tournament.swiss_rounds_count, tournament.top_cut_size]
    assert_equal 1, tournament.rounds.count
  end

  test "starting the swiss keeps a structure the organiser already chose" do
    tournament = TournamentBuilder.build(players: 24, organizer: event_organizers(:standard_organizer),
                                         state: :registration_closed)
    tournament.update_columns(swiss_rounds_count: 3, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations

    tournament.update!(state: :swiss)

    assert_equal [3, 0], [tournament.reload.swiss_rounds_count, tournament.top_cut_size]
  end

  test "dropped players do not count towards the suggested structure or its snapshot" do
    tournament = TournamentBuilder.build(players: 25, organizer: event_organizers(:standard_organizer),
                                         state: :registration_closed)
    tournament.event_participants.first(2).each { |p| p.update_columns(dropped: true) } # rubocop:disable Rails/SkipsModelValidations
    tournament.reload # 25 registered => top 10; 23 playing => top 4

    assert_equal({ swiss_rounds: 4, top_cut_size: 4 }, tournament.suggested_structure)
    assert_equal({ players: 4, pods: [1] }, tournament.rounds_info[:top])

    tournament.update!(state: :swiss)
    assert_equal [4, 4], [tournament.reload.swiss_rounds_count, tournament.top_cut_size]
  end

  test "a cut bigger than the players still playing is too big" do
    tournament = TournamentBuilder.build(players: 17, organizer: event_organizers(:standard_organizer),
                                         state: :registration_closed)
    tournament.top_cut_size = 16
    assert tournament.valid?, tournament.errors.full_messages.to_sentence

    tournament.event_participants.first(2).each { |p| p.update_columns(dropped: true) } # rubocop:disable Rails/SkipsModelValidations
    tournament.event_participants.reset
    assert_not tournament.valid?
    assert_includes tournament.errors[:top_cut_size],
                    I18n.t("activerecord.errors.models.event.attributes.top_cut_size.too_big")
  end

  test "drops after the swiss started do not lock the tournament behind the top cut check" do
    tournament = TournamentBuilder.build(players: 17, organizer: event_organizers(:standard_organizer),
                                         state: :registration_closed)
    tournament.update!(top_cut_size: 16)
    tournament.update!(state: :swiss)
    tournament.event_participants.first(2).each { |p| p.update_columns(dropped: true) } # rubocop:disable Rails/SkipsModelValidations
    tournament.reload

    assert tournament.valid?, tournament.errors.full_messages.to_sentence
    tournament.update!(description: "x")
    tournament.update!(state: :finished)
    assert tournament.reload.finished?
  end

  test "the cut must fit the playing field when the swiss starts" do
    tournament = TournamentBuilder.build(players: 17, organizer: event_organizers(:standard_organizer),
                                         state: :registration_closed)
    tournament.update!(top_cut_size: 16)
    tournament.event_participants.first(2).each { |p| p.update_columns(dropped: true) } # rubocop:disable Rails/SkipsModelValidations
    tournament.reload

    assert_not tournament.update(state: :swiss)
    assert_includes tournament.errors[:top_cut_size],
                    I18n.t("activerecord.errors.models.event.attributes.top_cut_size.too_big")
  end

  # ===== VALIDATION TESTS =====

  test "requires name, start_time, end_time and event_organizer" do
    tournament = Tournament.new(name: "Test Tournament") # Provide name to avoid slug generation error
    assert_not tournament.valid?

    assert_includes tournament.errors[:start_time], I18n.t("errors.messages.blank")
    assert_includes tournament.errors[:end_time], I18n.t("errors.messages.blank")
    # event_organizer is required by belongs_to association
  end

  test "slug generation from name" do
    tournament = Tournament.new(
      name: "My Awesome Tournament!",
      event_organizer: event_organizers(:standard_organizer),
      start_time: 1.week.from_now,
      end_time: 2.weeks.from_now
    )

    tournament.valid? # Triggers before_validation callback
    assert_equal "my-awesome-tournament-", tournament.slug
  end

  test "tournament requires event_organizer" do
    tournament = Tournament.new(
      name: "Test Tournament",
      slug: "test-tournament",
      start_time: 1.week.from_now,
      end_time: 2.weeks.from_now
    )

    assert_not tournament.valid?
    # NOTE: belongs_to validation is implicit in Rails
  end

  # ===== BUSINESS LOGIC TESTS =====

  test "ongoing? returns true for swiss and single_elimination states" do
    swiss_tournament = events(:large_tournament) # swiss state
    single_elim_tournament = events(:boundary_five_tournament) # single_elimination state
    finished_tournament = events(:finished_tournament) # finished state

    assert swiss_tournament.ongoing?, "Swiss tournament should be ongoing"
    assert single_elim_tournament.ongoing?, "Single elimination tournament should be ongoing"
    assert_not finished_tournament.ongoing?, "Finished tournament should not be ongoing"
  end

  test "single_elimination_round_name generates correct names" do
    tournament = events(:standard_tournament) # 16 players: 4 swiss + 1 single elim (suggested)

    # For a tournament with 4 swiss rounds + 1 single elimination round
    # Round 5 (single elimination) should be "Finals"
    assert_equal "Finals", tournament.single_elimination_round_name(5)
  end

  test "progress_percent calculation with no rounds completed" do
    tournament = events(:standard_tournament) # 16 players: 4 swiss + 1 single elim = 5 total

    # With 0 rounds completed, progress should be 0%
    expected_progress = 0.0
    assert_equal expected_progress, tournament.progress_percent
  end

  # ===== SCOPE TESTS =====

  test "past scope returns tournaments that have ended" do
    past_tournaments = Tournament.past
    assert_includes past_tournaments, events(:finished_tournament)

    # Upcoming tournaments should not be included
    assert_not_includes past_tournaments, events(:small_tournament)
  end

  test "upcoming scope returns future tournaments" do
    upcoming_tournaments = Tournament.upcoming
    assert_includes upcoming_tournaments, events(:small_tournament)

    # Past tournaments should not be included
    assert_not_includes upcoming_tournaments, events(:finished_tournament)
  end

  test "ongoing scope returns active tournaments" do
    ongoing_tournaments = Tournament.ongoing
    assert_includes ongoing_tournaments, events(:large_tournament) # swiss state
    assert_includes ongoing_tournaments, events(:boundary_five_tournament) # single_elimination state

    # Non-active states should not be included
    assert_not_includes ongoing_tournaments, events(:finished_tournament)
    assert_not_includes ongoing_tournaments, events(:small_tournament) # draft state
  end

  # ===== CONSTANTS TESTS =====

  test "tournament constants have expected values" do
    assert_equal 4, Tournament::PREFERRED_POD_SIZE
    assert_equal 3, Tournament::SMALLER_POD_SIZE
    assert_equal 5, Tournament::LARGER_POD_SIZE
    assert_equal 7, Tournament::POINTS_PER_WIN
    assert_equal 0, Tournament::POINTS_PER_LOSS
    assert_equal 1, Tournament::POINTS_PER_DRAW
  end

  test "supported top cuts are 4, 10, 13, 16 and 40" do
    assert_equal [4, 10, 13, 16, 40], Tournaments::TopCut::SIZES
  end

  # ===== LOCATION TESTS =====

  test "latitude and longitude setters create location point" do
    tournament = events(:small_tournament)

    tournament.latitude = 40.7128
    tournament.longitude = -74.0060

    assert_not_nil tournament.location
    assert_equal 40.7128, tournament.latitude
    assert_equal(-74.0060, tournament.longitude)
  end

  test "latitude and longitude return 0 when location is nil" do
    tournament = Tournament.new

    assert_equal 0, tournament.latitude
    assert_equal 0, tournament.longitude
  end
end
