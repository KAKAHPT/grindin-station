# frozen_string_literal: true

# Events the export tests read. Multiplayer, 16 players: round 1 (pod 1 seat 1 wins, pod 2 seat 2 wins, pod 3
# draws, pod 4 seat 4 wins) and round 2 (seat 1 wins everywhere) closed; one player has a Wizards e-mail and
# one dropped after round 2. 1v1, 5 players: round 1 closed (table 1 won 2-1, table 2 drawn 1-1) with a bye.
module ExportTournament
  BOM = "﻿"

  def build_export_tournament
    t = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
    t.update_columns(swiss_rounds_count: 3, top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
    t.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(t, winners: { 1 => 0, 2 => 1, 3 => :draw, 4 => 3 })
    t.rounds.create!(type: SwissRound, number: 2)
    TournamentBuilder.play_round!(t, winners: { 1 => 0, 2 => 0, 3 => 0, 4 => 0 })
    t.reload
  end

  def build_export_1v1_tournament
    t = TournamentBuilder.build(players: 5, organizer: event_organizers(:standard_organizer), format: "one_v_one")
    t.update_columns(swiss_rounds_count: 3, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
    t.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_1v1_round!(t, scores: { 1 => [2, 1], 2 => [1, 1] })
    t.reload
  end

  def participant_named(event, name)
    event.event_participants.joins(player: :user).find_by!(users: { name: name })
  end

  # Parses an export: asserts the BOM and CRLF line ends, answers the rows (header included).
  def parse_export(csv)
    assert csv.start_with?(BOM), "missing UTF-8 BOM"
    assert_equal Encoding::UTF_8, csv.encoding
    body = csv.delete_prefix(BOM)
    assert body.end_with?("\r\n"), "rows must end with CRLF"
    assert_no_match(/(?<!\r)\n/, body, "bare LF line end")
    CSV.parse(body, row_sep: "\r\n")
  end

  def without_n_plus_one
    Prosopite.scan
    yield
  ensure
    Prosopite.finish
  end
end
