# frozen_string_literal: true

# Follow / unfollow a person by handle; comes back to where the button was.
class FollowsController < ApplicationController
  def create
    user = User.find_by!(handle: params.expect(:handle))
    current_user.follows.find_or_create_by!(followed: user) unless user == current_user
    redirect_back_or_to(profile_path(user.handle), notice: t("follows.following", name: user.display_name))
  end

  def destroy
    user = User.find_by!(handle: params.expect(:handle))
    current_user.follows.where(followed: user).destroy_all
    redirect_back_or_to(profile_path(user.handle), notice: t("follows.unfollowed", name: user.display_name))
  end
end
