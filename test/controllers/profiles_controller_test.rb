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

  test "the public profile never shows the Wizards e-mail" do
    @owner.player.update!(wizards_email: "secret-wiz@example.com")

    get profile_path("rita")

    assert_response :success
    assert_no_match(/secret-wiz@example\.com/, response.body)
  end

  test "a profile with no events explains what will appear, and offers the owner the events list" do
    newcomer = User.create!(name: "Newcomer", email_address: "new-#{SecureRandom.hex(3)}@example.com",
                            password: "password123", handle: "newcomer")

    get profile_path("newcomer")

    assert_response :success
    assert_select "[data-profile-empty]", text: /No events played yet.*after the first tournament/m
    assert_select "[data-profile-empty] a[data-find-events]", count: 0

    post session_path, params: { session: { email_address: newcomer.email_address, password: "password123" } }
    get profile_path("newcomer")

    assert_select "[data-profile-empty] a[data-find-events][href=?]", events_path, text: "Find an event"
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

  test "shows the header and the finished events with date, name, position and organizer" do
    @owner.update!(country: "pt", bio: "Grinding since 2019.\n\nBlue player.")

    get profile_path("rita")

    assert_response :success
    assert_select "p", text: "@rita"
    assert_select "[data-profile-country]", text: "Portugal"
    assert_select "[data-profile-bio] p", 2
    assert_select "[data-profile-initials]", text: "RG"
    assert_select "[data-profile-follow] a[data-follow=sign_in]", text: "Follow"
    assert_select "[data-profile-comments]"
    assert_select "tr[data-event]", 1 do
      assert_select "a[href=?]", tournament_path(@event), text: @event.name
      assert_select "[data-result]", text: "3rd of 4"
    end
    assert_select "tr[data-event-detail][hidden]", 1 do
      assert_select "[data-wld]", text: /\A\d-\d-\d\z/
    end
  end

  test "three events: the band totals, achievements and commanders" do
    three_events

    get profile_path("rita")

    assert_response :success
    win_rate = Profiles::Summary.call(Profiles::History.call(user: @owner)).win_rate
    assert_select "[data-profile-summary]" do
      assert_select "[data-stat=events]", text: "3"
      assert_select "[data-stat=top_cuts]", text: "1"
      assert_select "[data-stat=win_rate]", text: win_rate ? "#{win_rate}%" : "–"
      assert_select "[data-stat=conversion]", text: "33%"
      assert_select "[data-ach=wins]", text: "1"
      assert_select "[data-ach=top4]", text: "3"
      assert_select "[data-ach=cuts]", text: "1"
      assert_select "[data-commanders] li", 2
      assert_select "[data-commanders] li:nth-child(1)", text: /Kinnan, Bonder Prodigy\s*1 · 33%/
      assert_select "[data-commanders] li:nth-child(2)", text: /Mono-U Tempo\s*1 · 33%/
    end
  end

  test "three events: the toolbar with search, years newest first, the season and the count" do
    three_events

    get profile_path("rita")

    assert_select "[data-profile-tools]" do
      assert_select "input[type=search][data-profile-events-target=search][placeholder=?]",
                    "Search events, organizers, commanders…"
      assert_select "button[data-year=all]", text: "All"
      years = css_select("button[data-year]").pluck("data-year")
      assert_equal ["all", Date.current.year.to_s, 1.year.ago.year.to_s], years
      assert_select "select[data-season] option", 2
      assert_select "select[data-season] option[value=all]", text: "All seasons"
      assert_select "select[data-season] option[value=?]", "Standard Circuit"
      assert_select "[data-count]", text: "3 of 3 events"
    end
  end

  test "three events: table rows with their data, the cut tag, a grey result and the 1v1 detail" do
    cut, one_v_one = three_events

    get profile_path("rita")

    assert_select "[data-profile-events]" do
      assert_select "th[data-sort]", 3
      assert_select "tr[data-event]", 3
      assert_select "tr[data-event] .text-accent", 0
    end
    assert_select "[data-more]", 0 # three events fit in the first six
    assert_select "tr[data-event][data-name=?]", cut.name do |(row)|
      assert_cut_row(row, cut)
      assert_select "td:nth-child(2) [data-cut-tag]", text: "Top 4"
      assert_select "button[aria-expanded=false][aria-controls] [data-sign]", text: "+"
    end
    one_v_one_row = assert_select("tr[data-event][data-name=?][data-cut='0'][data-season='']", one_v_one.name).first
    detail_id = one_v_one_row.at_css("button[aria-controls]")["aria-controls"]
    assert_select "tr[data-event-detail][hidden]##{detail_id}", text: /1v1 · no seats/
  end

  test "a multiplayer detail row shows record, win rate, seats taken, seat 1 share and the rounds" do
    get profile_path("rita")

    assert_select "tr[data-event-detail]" do
      assert_select "*", text: /Record/
      assert_select "*", text: /Win rate/
      assert_select "*", text: /Seats taken/
      assert_select "*", text: /of 1 round\b/
      assert_select "[data-round-seat]", 1
      assert_select "[data-round-seat]", text: /\AR1 · seat \d\z/
    end
  end

  test "more than six events: all rows rendered and the More button" do
    6.times { |i| played_event([@owner], position: i + 1, start_time: (i + 1).weeks.ago) }

    get profile_path("rita")

    assert_select "tr[data-event]", 7
    assert_select "[data-more] button, button[data-more]", text: "Show all 7 events"
  end

  test "the team tag shows after the name only when set" do
    get profile_path("rita")
    assert_select "[data-team]", 0

    @owner.update!(team: "Porto Grinders")
    get profile_path("rita")
    assert_select "[data-team]", text: "Porto Grinders"
  end

  test "a user without finished events: the band at zero, the empty card and no toolbar" do
    @stranger.update!(handle: "outra")

    get profile_path("outra")

    assert_response :success
    assert_select "[data-profile-summary] [data-stat=events]", text: "0"
    assert_select "[data-profile-summary] [data-stat=win_rate]", text: "–"
    assert_select "[data-profile-summary] [data-ach=wins]", text: "0"
    assert_select "[data-profile-summary] [data-commanders] li", text: "–"
    assert_select "[data-profile-tools]", 0
    assert_select "[data-profile-events]", 0
    assert_select "[data-profile-empty] p", text: "No events played yet."
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
    assert_select "[data-result]", text: "3.º de 4"
    assert_select "[data-profile-follow] a[data-follow=sign_in]", text: "Seguir"
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
    assert_select "tr[data-event]", 5
    puts "\n[query budget] profile with 5 events: #{count}" if ENV["QUERY_BUDGET_REPORT"]
    assert_operator count, :<=, 12
  end

  test "standings link the name only for public profiles" do
    @mate.update!(visibility: "private")

    get play_standings_path(@event.slug)

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

  def assert_cut_row(row, cut)
    date = cut.start_time.to_date
    expected = { "data-date" => date.iso8601, "data-year" => date.year.to_s, "data-season" => "Standard Circuit",
                 "data-commander" => "Kinnan, Bonder Prodigy", "data-organizer" => cut.event_organizer.name,
                 "data-format" => I18n.t("play.header.multiplayer"), "data-position" => "2",
                 "data-participants" => "4", "data-cut" => "1" }
    assert_equal expected, row.to_h.slice(*expected.keys)
    assert_equal(2, %w[data-wins data-losses data-draws].sum { |key| row[key].to_i }) # two swiss rounds
  end

  # The plain event of the setup plus a finished Top-4 tournament in a circuit where Rita reached the
  # single-elimination round (2nd, Kinnan) and a 1v1 a year ago that she won.
  def three_events
    cut =
      history_event(@owner, position: 2, winner_seat: 0, top_cut_size: 4, rounds: 2, start_time: 1.day.ago,
                            circuit_id: circuits(:standard_circuit).id) do |t|
        participant_of(t, @owner).update!(decklist: "Kinnan, Bonder Prodigy")
        t.rounds.create!(type: SingleEliminationRound, number: 3)
      end
    [cut, history_event(@owner, position: 1, format: "one_v_one", start_time: 1.year.ago) do |t|
      participant_of(t, @owner).update!(decklist: "Mono-U Tempo")
    end]
  end

  def participant_of(event, user) = event.event_participants.find_by(player: user.player)

  # As Profiles::HistoryTest#played_event: a 4-player tournament with the user, `rounds` swiss rounds played,
  # then finished; the block runs before (a cut round, a decklist).
  def history_event(user, position:, winner_seat: :draw, **attrs)
    event = TournamentBuilder.build(players: 3, organizer: event_organizers(:standard_organizer), state: :swiss,
                                    format: attrs.delete(:format) || "multiplayer")
    event.event_participants.create!(player: user.player, accepted_terms: true)
    rounds = attrs.delete(:rounds) || 1
    event.update_columns(swiss_rounds_count: rounds, top_cut_size: 0, **attrs) # rubocop:disable Rails/SkipsModelValidations
    play_swiss_rounds(event, rounds, winner_seat)
    yield event if block_given?
    participant_of(event, user).update_columns(final_position: position) # rubocop:disable Rails/SkipsModelValidations
    event.update_column(:state, :finished) # rubocop:disable Rails/SkipsModelValidations
    event.reload
  end

  def play_swiss_rounds(event, rounds, winner_seat)
    rounds.times do |i|
      event.rounds.create!(type: SwissRound, number: i + 1)
      TournamentBuilder.play_round!(event, winners: { 1 => winner_seat })
    end
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
