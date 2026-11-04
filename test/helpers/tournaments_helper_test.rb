# frozen_string_literal: true

require "test_helper"

class TournamentsHelperTest < ActionView::TestCase
  test "dollar prices keep the dollar format under the pt locale" do
    I18n.with_locale(:pt) do
      assert_equal "$10.00", number_to_currency(10, number_to_currency_options("dollar"))
    end
  end

  test "euro prices use the euro format under the pt locale" do
    I18n.with_locale(:pt) do
      assert_equal "10,00 €", number_to_currency(10, number_to_currency_options("euro"))
    end
  end

  test "structure suggestion names the suggested rounds and cut" do
    t = TournamentBuilder.build(players: 24, organizer: event_organizers(:standard_organizer),
                                state: :registration_open)
    assert_equal "Suggested for 24 players: 4 swiss rounds, top 10", structure_suggestion(t)
    I18n.with_locale(:pt) do
      assert_equal "Sugestão para 24 jogadores: 4 rondas Swiss, top 10", structure_suggestion(t)
    end
  end

  test "structure suggestion without a cut says so" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), state: :registration_open)
    assert_equal "Suggested for 4 players: 3 swiss rounds, no cut", structure_suggestion(t)
    I18n.with_locale(:pt) do
      assert_equal "Sugestão para 4 jogadores: 3 rondas Swiss, sem corte", structure_suggestion(t)
    end
  end

  test "a 1v1 straight single elimination suggestion names the cut, not swiss rounds" do
    t = TournamentBuilder.build(players: 6, organizer: event_organizers(:standard_organizer), format: "one_v_one",
                                state: :registration_open)
    assert_equal "Suggested for 6 players: single elimination, top 8", structure_suggestion(t)
    I18n.with_locale(:pt) do
      assert_equal "Sugestão para 6 jogadores: eliminação direta, top 8", structure_suggestion(t)
    end
  end

  test "structure suggestion counts only players still playing" do
    t = TournamentBuilder.build(players: 25, organizer: event_organizers(:standard_organizer),
                                state: :registration_open)
    t.event_participants.first(2).each { |p| p.update_columns(dropped: true) } # rubocop:disable Rails/SkipsModelValidations
    assert_equal "Suggested for 23 players: 4 swiss rounds, top 4", structure_suggestion(t.reload)
  end

  test "no structure suggestion below 4 players" do
    assert_nil structure_suggestion(Tournament.new)
    t = TournamentBuilder.build(players: 3, organizer: event_organizers(:standard_organizer), state: :registration_open)
    assert_nil structure_suggestion(t)
  end

  test "top cut options start with no cut, then every supported size" do
    assert_equal [["No cut", 0], ["Top 4", 4], ["Top 10", 10], ["Top 13", 13], ["Top 16", 16], ["Top 40", 40]],
                 top_cut_options
  end
end
