# frozen_string_literal: true

require "test_helper"

# The request path kept for error and audit records never carries the password-reset token.
class RequestPathRedactionTest < ActiveSupport::TestCase
  test "the reset token is filtered out of the recorded path" do
    request = ActionDispatch::TestRequest.create("PATH_INFO" => "/passwords/abc123/edit",
                                                 "action_dispatch.request.path_parameters" => { token: "abc123" })

    assert_equal "/passwords/[FILTERED]/edit", ApplicationController.redacted_path(request)
  end

  test "other paths are kept as they are" do
    request = ActionDispatch::TestRequest.create("PATH_INFO" => "/t/open-cup/pairings",
                                                 "action_dispatch.request.path_parameters" => { slug: "open-cup" })

    assert_equal "/t/open-cup/pairings", ApplicationController.redacted_path(request)
  end
end
