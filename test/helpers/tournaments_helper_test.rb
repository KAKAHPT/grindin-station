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
end
