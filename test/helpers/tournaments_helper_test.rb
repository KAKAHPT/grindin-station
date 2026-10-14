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
    t = TournamentBuilder.build(players: 24, organizer: event_organizers(:standard_organizer), state: :registration_open)
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

  test "top cut options start with no cut, then every supported size" do
    assert_equal [["No cut", 0], ["Top 4", 4], ["Top 10", 10], ["Top 13", 13], ["Top 16", 16], ["Top 40", 40]],
                 top_cut_options
  end
end
