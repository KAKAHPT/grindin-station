# frozen_string_literal: true

abort("Seeds are for development only") if Rails.env.production?

# Create an initial list of users
users = User.create(
  [
    { name: "Fábio", email_address: "fabio@grindin-station.test", password: "123qwe123" },
    { name: "Simão", email_address: "simao@grindin-station.test", password: "123qwe123" },
    { name: "Bandeira", email_address: "bandeira@grindin-station.test", password: "123qwe123" },
    { name: "Esgaio", email_address: "esgaio@grindin-station.test", password: "123qwe123" },
    { name: "Nuno", email_address: "nuno@grindin-station.test", password: "123qwe123" },
    { name: "Pedro", email_address: "pedro@grindin-station.test", password: "123qwe123" },
    { name: "Joao", email_address: "joao@grindin-station.test", password: "123qwe123" },
    { name: "Gil", email_address: "gil@grindin-station.test", password: "123qwe123" },
    { name: "Lucas", email_address: "lucas@grindin-station.test", password: "123qwe123" },
    { name: "Artur", email_address: "artur@grindin-station.test", password: "123qwe123" },
    { name: "Brandao", email_address: "brandao@grindin-station.test", password: "123qwe123" },
    { name: "Chico", email_address: "chico@grindin-station.test", password: "123qwe123" },
    { name: "Demerson", email_address: "demerson@grindin-station.test", password: "123qwe123" },
    { name: "Guilherme", email_address: "guilherme@grindin-station.test", password: "123qwe123" },
    { name: "Olivio", email_address: "olivio@grindin-station.test", password: "123qwe123" },
    { name: "Tiago", email_address: "tiago@grindin-station.test", password: "123qwe123" },
    { name: "Jose", email_address: "jose@grindin-station.test", password: "123qwe123" },
    { name: "Vanessa", email_address: "vanessa@grindin-station.test", password: "123qwe123" },
    { name: "Antonio", email_address: "antonio@grindin-station.test", password: "123qwe123" },
    { name: "Fernando", email_address: "fernando@grindin-station.test", password: "123qwe123" },
    { name: "Francisco", email_address: "francisco@grindin-station.test", password: "123qwe123" },
    { name: "Afonso", email_address: "afonso@grindin-station.test", password: "123qwe123" },
    { name: "Roberto", email_address: "roberto@grindin-station.test", password: "123qwe123" },
    { name: "Bonifacio", email_address: "bonifacio@grindin-station.test", password: "123qwe123" },
    { name: "Carlos", email_address: "carlos@grindin-station.test", password: "123qwe123" },
    { name: "Joel", email_address: "joel@grindin-station.test", password: "123qwe123" },
    { name: "Emanuel", email_address: "emanuel@grindin-station.test", password: "123qwe123" },
    { name: "Vitor", email_address: "vitor@grindin-station.test", password: "123qwe123" },
    { name: "Hugo", email_address: "hugo@grindin-station.test", password: "123qwe123" },
    { name: "Mario", email_address: "mario@grindin-station.test", password: "123qwe123" },
    { name: "Manuel", email_address: "manuel@grindin-station.test", password: "123qwe123" },
    { name: "Max", email_address: "max@grindin-station.test", password: "123qwe123" }
  ]
)

# Create an initial event organizer
to = EventOrganizer.create!(
  user: User.create({ name: "Kakah", email_address: "kakah@grindin-station.test", password: "123qwe123" })
)

other_to = EventOrganizer.create!(
  user: User.create({ name: "Virgilio", email_address: "virgilio@grindin-station.test", password: "123qwe123" })
)

# Create a couple of example events
events = Tournament.create!(
  [
    {
      name: "Uneven Pods Tournament",
      state: :registration_open,
      prizes:
        <<~PRIZES,
          - 1st: Timetwister
          - 2nd: Gaea's Cradle
          - 3rd: Mox Diamond
          - 4th: Volcanic Island
        PRIZES
      event_organizer: to,
      address: "Rua Princesa Cindazunda, 61, Coimbra",
      schedule:
        <<~SCHEDULE,
          **Day One**

          - 8:00am Checkin
          - 9:00am Player meeting
          - 9:15am Round 1
          - Round 2
          - Lunch Break
          - Round 3
          - Round 4
          - Round 5
          - Round 6

          **Day two**

          - 8:45 Player meeting
          - 9:00 Round 7
          - Top 40
          - Top 16
          - Top 4
        SCHEDULE
      participants_range: 10..256,
      price: 35,
      currency: :euro,
      rules:
        <<~RULES,
          Format: Commander
          REL: Competitive
          Multiplayer Addendum: https://juizes-mtg-portugal.github.io
          Playtest cards: Allowed, no limit.
        RULES
      cover: File.open("test/fixtures/files/cover1.jpg"),
      start_time: 2.weeks.from_now,
      end_time: 2.weeks.from_now + 8.hours
    },
    {
      name: "Last Week Tournament example",
      state: :registration_open,
      event_organizer: other_to,
      cover: File.open("test/fixtures/files/cover2.jpg"),
      start_time: 5.minutes.ago,
      end_time: 10.hours.from_now
    },
    {
      name: "Qualifier for EU Champ",
      state: :registration_open,
      event_organizer: to,
      cover: File.open("test/fixtures/files/cover3.jpg"),
      start_time: 1.week.from_now,
      end_time: 1.week.from_now + 1.day
    },
    {
      name: "FNM Commander",
      state: :registration_open,
      event_organizer: to,
      cover: File.open("test/fixtures/files/cover4.jpg"),
      start_time: 1.week.from_now,
      end_time: 1.week.from_now + 1.day
    }
  ]
)

# Add players to the events

users.map(&:player)[0...21].each do |p|
  next if p.blank?

  EventParticipant.create(
    {
      event: events.first,
      player: p,
      decklist: "https://moxfield.com/decklist/#{p.user.email_address.split('@').first}",
      accepted_terms: true
    }
  )
end

events[1..].each do |event|
  users.map(&:player).each do |p|
    next if p.blank?

    EventParticipant.create(
      {
        event: event,
        player: p,
        decklist: "https://moxfield.com/decklist/#{p.user.email_address.split('@').first}",
        accepted_terms: true
      }
    )
  end
end

events[1].update(state: :registration_closed)
events[1].update(state: :swiss)
