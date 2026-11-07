# frozen_string_literal: true

# A player creates a team from the account page and owns it (one accepted team per player).
class TeamsController < ApplicationController
  rate_limit to: 5, within: 10.minutes, only: :create, by: -> { current_user.id },
             with: -> { redirect_to account_path(anchor: "team"), alert: t("flash.alert.try_again_later") }

  def create
    return back_to_team alert: t("teams.flash.already_in_a_team") if current_user.team_membership

    team = create_team(params.expect(team: [:name])[:name])
    back_to_team notice: t("teams.flash.created", name: team.name)
  rescue ActiveRecord::RecordInvalid => e
    back_to_team alert: e.record.errors.full_messages.to_sentence
  end

  private

  def create_team(name)
    Team.transaction do
      Team.create!(name: name, owner: current_user).tap do |team|
        team.memberships.create!(user: current_user, status: "accepted")
      end
    end
  end

  def back_to_team(**flash)
    redirect_to account_path(locale: params[:locale], anchor: "team"), **flash
  end
end
