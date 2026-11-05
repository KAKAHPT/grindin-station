# frozen_string_literal: true

# A player's public profile (/p/:handle). Hidden profiles answer 404, so their existence is not revealed.
class ProfilesController < ApplicationController
  allow_unauthenticated_access
  layout "public"

  def show
    @user = User.find_by(handle: params.expect(:handle))
    raise ActiveRecord::RecordNotFound unless @user&.profile_visible_to?(current_user)

    @history = Profiles::History.call(user: @user)
    @summary = Profiles::Summary.call(@history)
  end
end
