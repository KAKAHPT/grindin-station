# frozen_string_literal: true

require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
  setup do
    @owner = new_user("Rita Grind", handle: "rita")
    @mate = new_user("Duarte Mesa")
    @stranger = new_user("Outra Pessoa")
    @event = played_event([@owner, @mate], position: 3)
  end

  # visibility × viewer: anonymous, a player who shares an event, the user themself
  {
    "public" => { anonymous: true, mate: true, owner: true, stranger: true },
    "participants" => { anonymous: false, mate: true, owner: true, stranger: false },
    "private" => { anonymous: false, mate: false, owner: true, stranger: false }
  }.each do |visibility, viewers|
    viewers.each do |viewer, visible|
      test "#{visibility} profile is #{visible ? 'shown' : 'hidden'} to #{viewer}" do
        @owner.update!(visibility: visibility)
        sign_in(instance_variable_get(:"@#{viewer}")) unless viewer == :anonymous

        get profile_path("rita")

        assert_response(visible ? :success : :not_found)
        assert_select "h1", text: "Rita Grind" if visible
      end
    end
  end

  test "an unknown handle is a 404" do
    get profile_path("nobody-here")

    assert_response :not_found
  end

  test "an anonymised user has no profile" do
    @owner.update!(anonymized_at: Time.current, handle: nil, name: "Removed")

    get profile_path("rita")

    assert_response :not_found
  end

  test "shows the header and the finished events with position, W-L-D and seats" do
    @owner.update!(country: "pt", bio: "Grinding since 2019.\n\nBlue player.")

    get profile_path("rita")

    assert_response :success
    assert_select "p", text: "@rita"
    assert_select "[data-profile-country]", text: "Portugal"
    assert_select "[data-profile-bio] p", 2
    assert_select "[data-profile-initials]", text: "RG"
    assert_select "button[disabled][title=?]", "Coming soon"
    assert_select "[data-profile-comments]"
    assert_select "[data-profile-event]", 1 do
      assert_select "a[href=?]", tournament_path(@event), text: @event.name
      assert_select "[data-position]", text: "3rd of 4"
      assert_select "[data-wld]", text: /\A\d-\d-\d\z/
      assert_select "span[role=img][aria-label]"
    end
  end

  test "shows the avatar when there is one" do
    @owner.avatar.attach(io: file_fixture("cover1.jpg").open, filename: "a.jpg", content_type: "image/jpeg")

    get profile_path("rita")

    assert_response :success
    assert_select "img[src*='a.jpg']"
    assert_select "[data-profile-initials]", count: 0
  end

  test "renders in portuguese" do
    get profile_path("rita", locale: "pt")

    assert_response :success
    assert_select "[data-position]", text: "3.º de 4"
    assert_select "button[disabled][title=?]", "Em breve"
  end

  test "the decklist shows only when the event shows decklists" do
    participation = @event.event_participants.find_by(player: @owner.player)
    participation.update!(decklist: "https://moxfield.com/decks/abc")

    get profile_path("rita")
    assert_select "a[href=?]", "https://moxfield.com/decks/abc", count: 0

    @event.update_column(:show_decklists, true) # rubocop:disable Rails/SkipsModelValidations
    get profile_path("rita")
    assert_select "a[href=?]", "https://moxfield.com/decks/abc"
  end

  test "events still running are not listed" do
    running = played_event([@owner], position: nil, state: :swiss)

    get profile_path("rita")

    assert_select "a", text: running.name, count: 0
  end

  test "the page runs a fixed number of queries for five events" do
    4.times { |i| played_event([@owner], position: i + 1, start_time: (i + 1).weeks.ago) }

    count = count_queries { get profile_path("rita") }

    assert_response :success
    assert_select "[data-profile-event]", 5
    puts "\n[query budget] profile with 5 events: #{count}" if ENV["QUERY_BUDGET_REPORT"]
    assert_operator count, :<=, 12
  end

  test "standings link the name only for public profiles" do
    @mate.update!(visibility: "private")

    get tournament_event_participants_path(@event)

    assert_response :success
    assert_select "a[href=?]", profile_path("rita"), text: "Rita Grind"
    assert_select "a[href=?]", profile_path(@mate.handle), count: 0
    assert_select "th", text: "Duarte Mesa"
  end

  test "organizer form saves show_decklists" do
    sign_in(users(:organizer_user))
    tournament = events(:small_tournament)

    patch organizer_tournament_path(tournament), params: { tournament: { show_decklists: "1" } }

    assert tournament.reload.show_decklists
  end

  private

  def new_user(name, handle: nil)
    User.create!(name: name, handle: handle, email_address: "#{name.parameterize}-#{SecureRandom.hex(3)}@example.com",
                 password: "password123")
  end

  def sign_in(user)
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
  end

  def played_event(users, position:, state: :finished, start_time: Time.current)
    event = TournamentBuilder.build(players: 4 - users.size, organizer: event_organizers(:standard_organizer),
                                    state: :swiss)
    users.each_with_index do |user, i|
      event.event_participants.create!(player: user.player, accepted_terms: true, final_position: (position if i.zero?))
    end
    event.update_columns(swiss_rounds_count: 1, top_cut_size: 0, start_time: start_time) # rubocop:disable Rails/SkipsModelValidations
    event.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(event, winners: { 1 => 0 })
    event.update_column(:state, state) # rubocop:disable Rails/SkipsModelValidations
    event.reload
  end

  def count_queries(&block)
    count = 0
    counter =
      lambda do |_name, _start, _finish, _id, payload|
        count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:cached]
      end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
