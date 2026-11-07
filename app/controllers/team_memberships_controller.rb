# frozen_string_literal: true

# Joining a team: a player requests a place (the owner accepts), an owner invites a player by handle (the player
# accepts); either side declines, a member leaves, an owner removes a member.
class TeamMembershipsController < ApplicationController
  before_action :load_membership, only: %i[update destroy]

  def create
    team = Team.find(params.expect(:team_id))
    membership = params[:handle].present? ? invite(team) : request_place(team)
    return failed(membership) unless membership.persisted?

    notify(membership)
    back_to_team notice: t("teams.flash.#{membership.status}", name: team.name)
  end

  # Accepting: the owner on a request, the player on an invitation.
  def update
    return back_to_team alert: t("flash.alert.not_allowed") unless accepter == current_user
    return failed(@membership) unless @membership.update(status: "accepted")

    notify_accepted
    back_to_team notice: t("teams.flash.accepted", name: @membership.team.name)
  end

  # Declining, leaving or removing: the player or the team's owner.
  def destroy
    team = @membership.team
    return back_to_team alert: t("flash.alert.not_allowed") unless mine? || team.owned_by?(current_user)

    @membership.destroy!
    team.hand_over! if @membership.accepted? && team.owned_by?(@membership.user)
    back_to_team notice: t("teams.flash.left", name: team.name)
  end

  private

  def request_place(team)
    return refused(:already_in_a_team) if current_user.team_membership

    team.memberships.create(user: current_user, status: "requested")
  end

  def invite(team)
    return refused(:not_owner) unless team.owned_by?(current_user)

    user = User.find_by(handle: params[:handle].to_s.strip.delete_prefix("@"))
    return refused(:no_such_handle) unless user

    team.memberships.create(user: user, status: "invited")
  end

  def refused(error)
    TeamMembership.new.tap { |membership| membership.errors.add(:base, error) }
  end

  # The other side of the acceptance hears about it.
  def notify_accepted
    Notify.create_for([@membership.user_id, @membership.team.owner_id] - [current_user.id],
                      kind: "team_accepted", subject: @membership)
  end

  def accepter
    @membership.status == "requested" ? @membership.team.owner : @membership.user
  end

  def failed(membership)
    back_to_team alert: membership.errors.full_messages.to_sentence
  end

  def notify(membership)
    recipient = membership.status == "requested" ? membership.team.owner_id : membership.user_id
    Notify.create_for([recipient], kind: "team_#{membership.status}", subject: membership)
  end

  def mine? = @membership.user_id == current_user.id

  def load_membership
    @membership = TeamMembership.find(params.expect(:id))
  end

  def back_to_team(**flash)
    redirect_to account_path(locale: params[:locale], anchor: "team"), **flash
  end
end
