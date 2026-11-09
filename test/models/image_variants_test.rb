# frozen_string_literal: true

require "test_helper"

# Avatars and banners are served as resized variants: this resizes real images through libvips, so a gem bump
# that drops the image processor fails here instead of in production.
class ImageVariantsTest < ActiveSupport::TestCase
  test "an avatar is resized to its thumb and profile sizes" do
    user = users(:organizer_user)
    user.avatar.attach(io: file_fixture("cover1.jpg").open, filename: "cover1.jpg", content_type: "image/jpeg")

    assert_equal [96, 96], dimensions(user.avatar.variant(:thumb))
    assert_equal [256, 256], dimensions(user.avatar.variant(:profile))
  end

  test "a banner is resized to its card and wide sizes" do
    user = users(:organizer_user)
    user.banner.attach(io: file_fixture("cover2.jpg").open, filename: "cover2.jpg", content_type: "image/jpeg")

    assert_equal [800, 300], dimensions(user.banner.variant(:card))
    assert_equal [1600, 400], dimensions(user.banner.variant(:wide))
  end

  private

  def dimensions(variant)
    image = Vips::Image.new_from_buffer(variant.processed.download, "")
    [image.width, image.height]
  end
end
