# frozen_string_literal: true

require "test_helper"

class BrandingTest < ActionDispatch::IntegrationTest
  test "home page is branded Grindin Station" do
    get root_path
    assert_response :success
    assert_select "title", /Grindin Station/
    assert_no_match(/Canivete/, response.body)
  end
end
