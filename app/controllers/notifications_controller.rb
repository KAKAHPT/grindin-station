# frozen_string_literal: true

# The signed-in user's in-app notices, newest first.
class NotificationsController < ApplicationController
  def index
    @notifications = current_user.notifications.preload(subject: :event).order(created_at: :desc).limit(100)
  end

  def mark_all_read
    current_user.notifications.unread.update_all(read_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    redirect_to notifications_path(locale: params[:locale])
  end
end
