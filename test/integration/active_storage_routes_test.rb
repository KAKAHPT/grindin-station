# frozen_string_literal: true

require "test_helper"

# Uploads only go through the signed-in forms: Active Storage's direct-upload endpoints answer 404 to everyone, while
# the routes that serve the stored images (blobs, variants, the disk service) keep working.
class ActiveStorageRoutesTest < ActionDispatch::IntegrationTest
  BLOB_PARAMS = { blob: { filename: "x.jpg", byte_size: 10, checksum: "1B2M2Y8AsgTpgAmY7PhCfg==",
                          content_type: "image/jpeg" } }.freeze

  test "the direct-upload endpoint is refused and creates no blob" do
    assert_no_difference -> { ActiveStorage::Blob.count } do
      post "/rails/active_storage/direct_uploads", params: BLOB_PARAMS, as: :json
    end
    assert_response :not_found
  end

  test "a signed-in user cannot direct-upload either" do
    sign_in users(:player_one)

    assert_no_difference -> { ActiveStorage::Blob.count } do
      post "/rails/active_storage/direct_uploads", params: BLOB_PARAMS, as: :json
    end
    assert_response :not_found
  end

  test "the disk service refuses uploads, even with a valid token" do
    blob = ActiveStorage::Blob.create_before_direct_upload!(**BLOB_PARAMS[:blob])
    token = ActiveStorage.verifier.generate(
      { key: blob.key, content_type: blob.content_type, content_length: blob.byte_size, checksum: blob.checksum,
        service_name: blob.service_name }, expires_in: 5.minutes, purpose: :blob_token
    )

    put "/rails/active_storage/disk/#{token}", params: "0123456789", headers: { "Content-Type" => "image/jpeg" }

    assert_response :not_found
    assert_not blob.service.exist?(blob.key)
  end

  test "an avatar uploaded from the account form is shown and served" do
    user = users(:player_one)
    sign_in user

    patch account_path, params: { user: { avatar: fixture_file_upload("cover1.jpg", "image/jpeg") } }
    assert_redirected_to account_path
    assert user.reload.avatar.attached?

    get account_path
    src = css_select("img[src*='/rails/active_storage/representations/']").first&.[]("src")
    assert src, "the account page shows the avatar variant"

    assert_image_served src
  end

  test "an event cover is served as a variant and as the original file" do
    event = Event.find_by!(slug: "medium-tournament-registration-open")
    event.cover.attach(io: file_fixture("cover2.jpg").open, filename: "cover2.jpg", content_type: "image/jpeg")
    assert event.save

    get play_event_path(event.slug)
    assert_response :success
    src = response.body[%r{/rails/active_storage/representations/[^')"]+}]
    assert src, "the event header shows the cover variant"
    assert_image_served src

    assert_image_served rails_blob_path(event.cover, only_path: true)
  end

  private

  def sign_in(user)
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
  end

  # The redirect route sends the browser to the disk service, which answers the image.
  def assert_image_served(path)
    get path
    assert_response :redirect
    assert_match %r{/rails/active_storage/disk/}, response.location
    follow_redirect!
    assert_response :success
    assert_equal "image/jpeg", response.media_type
  end
end
