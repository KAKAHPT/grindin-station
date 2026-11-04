# frozen_string_literal: true

require "test_helper"

class EventParticipantTest < ActiveSupport::TestCase # rubocop:disable Metrics/ClassLength
  # ===== BASIC FIXTURE TEST =====

  test "fixtures load correctly" do
    assert_not_nil event_participants(:small_event_participant_one)
    assert_not_nil event_participants(:small_event_participant_two)
    participant = event_participants(:small_event_participant_one)
    assert_not_nil participant.event
    assert_not_nil participant.player
  end

  # ===== ASSOCIATIONS =====

  test "belongs to tournament and player" do
    participant = event_participants(:small_event_participant_one)
    assert_not_nil participant.event
    assert_not_nil participant.player
    assert_instance_of Tournament, participant.event
    assert_instance_of Player, participant.player
  end

  test "has many results with publishable scope" do
    participant = event_participants(:small_event_participant_one)
    # Should only return results from published/finished rounds
    results = participant.results
    assert_respond_to participant, :results
    # All results should be from finished rounds (publishable scope)
    results.each do |result|
      assert_not_nil result.round.finished_at, "Result should be from finished round"
    end
  end

  test "delegates name to player" do
    participant = event_participants(:small_event_participant_one)
    assert_equal participant.player.name, participant.name # Player delegates to user.name
    assert_equal "Player One", participant.name # From fixture
  end

  # ===== SCOPES =====

  test "playing scope excludes dropped participants" do
    # Create a dropped participant
    dropped_participant = EventParticipant.create!(
      event: events(:small_tournament),
      player: players(:player_one),
      dropped: true,
      accepted_terms: true
    )

    playing_participants = EventParticipant.playing
    event_participants(:small_event_participant_one).event.event_participants.playing

    # Should exclude dropped participant
    assert_not_includes playing_participants, dropped_participant
    # Should include active participants
    assert_includes playing_participants, event_participants(:small_event_participant_one)
  end

  test "not_eliminated scope excludes eliminated participants" do
    participant = event_participants(:medium_event_participant_two)

    # Create an eliminated result for this participant in a different round
    Result.create!(
      event_participant: participant,
      round: rounds(:ongoing_round), # Use different round to avoid uniqueness conflict
      type: "Eliminated"
    )

    not_eliminated = EventParticipant.not_eliminated
    # Should exclude eliminated participant
    assert_not_includes not_eliminated, participant
    # Should include other participants
    assert_includes not_eliminated, event_participants(:small_event_participant_one)
  end

  # ===== GAME STATISTICS METHODS =====

  test "number_of_wins counts Win results" do
    participant = event_participants(:small_event_participant_one)
    # Should count the win result from fixture
    assert_equal 1, participant.number_of_wins
  end

  test "number_of_draws counts Draw results" do
    participant = event_participants(:small_event_participant_three)
    # Should count the draw result from fixture
    assert_equal 1, participant.number_of_draws
  end

  test "number_of_losses counts Loss and Penalty results" do
    participant_with_loss = event_participants(:small_event_participant_two)
    participant_with_penalty = event_participants(:small_event_participant_four)

    # Loss result
    assert_equal 1, participant_with_loss.number_of_losses
    # Penalty result (inherits from Loss)
    assert_equal 1, participant_with_penalty.number_of_losses
  end

  test "an Advance in a swiss round is a bye worth points_bye, not an advancement" do
    participant = event_participants(:medium_event_participant_one) # Advance fixture in a SwissRound
    assert_equal 1, participant.number_of_byes
    assert_equal 0, participant.number_of_advancements
    assert_equal participant.event.points_bye, participant.match_points
  end

  test "number_of_advancements counts Advance results in single elimination rounds" do
    rounds(:medium_tournament_round_1).update_column(:type, "SingleEliminationRound") # rubocop:disable Rails/SkipsModelValidations
    participant = EventParticipant.find(event_participants(:medium_event_participant_one).id)
    assert_equal 1, participant.number_of_advancements
    assert_equal 0, participant.number_of_byes
  end

  # ===== POINT CALCULATION TESTS =====

  test "match_points calculation - Win result" do
    participant = event_participants(:small_event_participant_one) # Has 1 win
    expected_points = 1 * Tournament::POINTS_PER_WIN # 7 points
    assert_equal expected_points, participant.match_points
  end

  test "match_points calculation - Draw result" do
    participant = event_participants(:small_event_participant_three) # Has 1 draw
    expected_points = 1 * Tournament::POINTS_PER_DRAW # 1 point
    assert_equal expected_points, participant.match_points
  end

  test "match_points calculation - Loss result gets 0 points" do
    participant = event_participants(:small_event_participant_two) # Has 1 loss
    expected_points = 0 # 0 points for loss
    assert_equal expected_points, participant.match_points
  end

  test "match_points calculation - mixed results" do
    participant = event_participants(:small_event_participant_one)

    # Add a draw result to the participant who already has a win
    Result.create!(
      event_participant: participant,
      round: rounds(:medium_tournament_round_1),
      type: "Draw"
    )

    # Clear the memoized value
    participant.instance_variable_set(:@match_points, nil)

    expected_points = (1 * Tournament::POINTS_PER_WIN) + (1 * Tournament::POINTS_PER_DRAW) # 7 + 1 = 8
    assert_equal expected_points, participant.match_points
  end

  # ===== COMPLEX BUSINESS LOGIC TESTS =====

  test "playing? returns opposite of dropped" do
    active_participant = event_participants(:small_event_participant_one)
    assert active_participant.playing?
    assert_not active_participant.dropped

    # Create dropped participant
    dropped_participant = EventParticipant.create!(
      event: events(:small_tournament),
      player: players(:player_three),
      dropped: true,
      accepted_terms: true
    )

    assert_not dropped_participant.playing?
    assert dropped_participant.dropped
  end

  test "obfuscated_key returns first 5 characters with hash prefix" do
    participant = event_participants(:small_event_participant_one)
    expected_key = "##{participant.player.key.first(5)}"
    assert_equal expected_key, participant.obfuscated_key
  end

  test "rank_score calculation includes all components" do
    participant = event_participants(:small_event_participant_one) # Has 1 win (not just advance)

    # Debug the calculation components
    advancements = participant.number_of_advancements
    match_points = participant.match_points

    # Ensure we have valid numbers
    assert advancements >= 0
    assert match_points >= 0

    # Rank score should be positive
    rank_score = participant.rank_score
    assert rank_score.positive?, "Rank score should be positive"

    # Should be deterministic
    assert_equal rank_score, participant.rank_score # Memoized
  end

  # ===== VALIDATION TESTS =====

  test "requires accepted_terms on create" do
    participant = EventParticipant.new(
      event: events(:small_tournament),
      player: players(:player_one)
    )

    # Should be invalid without accepted_terms
    assert_not participant.valid?
    assert_includes participant.errors[:accepted_terms], "Must accept the terms and conditions"

    # Should be valid with accepted_terms
    participant.accepted_terms = true
    assert participant.valid?
  end

  test "counter_cache updates event_participants_count" do
    tournament = events(:small_tournament)
    initial_count = tournament.event_participants_count

    # Create new participant
    new_participant = EventParticipant.create!(
      event: tournament,
      player: players(:player_three),
      accepted_terms: true
    )

    # Counter should be updated
    assert_equal initial_count + 1, tournament.reload.event_participants_count

    # Destroy participant
    new_participant.destroy

    # Counter should be decremented
    assert_equal initial_count, tournament.reload.event_participants_count
  end

  test "win rate is wins over real games, byes excluded" do
    participant = EventParticipant.new
    participant.define_singleton_method(:results) { [Win.new, Win.new, Loss.new] }
    assert_in_delta 2.0 / 3, participant.win_rate
    assert_equal "66.7%", ApplicationController.helpers.win_rate_label(participant.win_rate)
  end

  test "win rate is nil with only a bye" do
    participant = EventParticipant.new
    participant.define_singleton_method(:results) { [Advance.new(round: SwissRound.new)] }
    assert_nil participant.win_rate
    assert_equal "–", ApplicationController.helpers.win_rate_label(participant.win_rate)
  end
end
