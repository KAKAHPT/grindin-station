# frozen_string_literal: true

require "test_helper"

module Accounts
  class AnonymizeTest < ActiveSupport::TestCase
    setup do
      @user = users(:player_one)
      @user.identities.create!(provider: "google_oauth2", uid: "g-1")
      @user.sessions.create!
      @participant = event_participants(:small_event_participant_one)
    end

    test "replaces personal data and frees the handle" do
      old_digest = @user.password_digest

      assert_same @user, Anonymize.call(user: @user)

      @user.reload
      assert_equal "Removed player", @user.name
      assert_match(/\Adeleted-[0-9a-f-]{36}@removed\.invalid\z/, @user.email_address)
      assert_not_equal old_digest, @user.password_digest
      assert_not @user.authenticate("password123")
      assert_nil @user.handle
      assert @user.anonymized_at.present?
      assert_empty @user.identities
      assert_empty @user.sessions
    end

    test "clears the team" do
      @user.update!(team: "Porto Grinders")

      Anonymize.call(user: @user)

      assert_nil @user.reload.team
    end

    test "clears the Wizards e-mail" do
      @user.player.update!(wizards_email: "wiz@example.com")

      Anonymize.call(user: @user)

      assert_nil @user.player.reload.wizards_email
    end

    test "clears the admin flag" do
      @user.update_column(:admin, true) # rubocop:disable Rails/SkipsModelValidations

      Anonymize.call(user: @user)

      assert_not @user.reload.admin?
    end

    test "keeps the player, its key and its event history" do
      player = @user.player
      key = player.key
      rank_score = @participant.rank_score

      assert_no_difference [-> { Player.count }, -> { EventParticipant.count }, -> { Result.count }] do
        Anonymize.call(user: @user)
      end

      assert_equal key, player.reload.key
      assert_equal @user, player.user
      assert_equal rank_score, EventParticipant.find(@participant.id).rank_score
    end

    test "update_key is skipped once anonymised" do
      Anonymize.call(user: @user)
      key = @user.player.reload.key

      @user.update!(name: "Somebody Else")

      assert_equal key, @user.player.reload.key
    end
  end
end
