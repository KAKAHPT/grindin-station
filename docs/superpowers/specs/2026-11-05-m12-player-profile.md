# M12 — Player profile: stats, achievements, filtered event table, team tag

**Date:** 2026-11-05. **Status:** approved design (mock `public/mock/profile-events.html`, table variant, grey tones). **Scope:** the public profile `/p/:handle` and the `/account` form. Nothing changes in tournaments, standings, pairings, exports or feeds.

## 1. Problem

The profile lists finished events as plain rows with the seat grid in each row. The organiser wants: a summary (stats, achievements, most played commanders), a search box and filters by year and season, a compact sortable table with a "+" per event that opens the details (record, win rate of that event, seats per round), a "show more" when there are many events, and a free-text team tag next to the name.

## 2. Decisions (with the organiser, on the mock)

| # | Decision |
|---|----------|
| D1 | Layout = table variant. Columns: Date · Event (with the top-cut tag after the name) · Result · Commander · "+". No seats and no W-L-D in the row. |
| D2 | Stats strip (grey band under the bio): **Events**, **Top cuts**, **Win rate**, **Conversion rate** (top cuts ÷ events). No seat-1 figure. |
| D3 | Achievements in one bordered rectangle inside the band, grey icons: **Wins** (trophy, position 1), **Top 4** (medal, position ≤ 4), **Top cuts** (shield, made the cut). |
| D4 | **Most played commanders**: top 4 commanders by number of events, each with count and share of the filtered events, thin grey bar. |
| D5 | Toolbar: search (event name, organizer, commander, format line), year segmented control (All + each year with events, newest first), season select (All + the circuits of the player's events). Stats, achievements and commanders follow the filter and the search. |
| D6 | Result cell: `3rd` white bold + ` of 48` muted, with a space. No colour for top cut. |
| D7 | Top-cut mark: grey outlined tag "Top 16" / "Top 4" (the event's cut size) right after the event name, 10 px gap. No yellow chip. |
| D8 | "+" button per row, grey outline; when open it turns **white** (ink background, ground text) and shows "–". The detail row shows: Record (W-L-D), Win rate of that event (wins ÷ games, "n games"), Seats taken (times at seats 1–4, seat 1 highlighted), Seat 1 share ("x% of n rounds"), and the per-round sequence ("R1 · seat 2", …). 1v1 events show "1v1 · no seats" instead of seats. |
| D9 | Show 6 rows by default; "Show all N events" expands, "Show less" collapses. Sorting by Date (default, newest first), Event (A–Z) and Result (best first) by clicking the header. |
| D10 | Team: free text `users.team`, optional, ≤ 30 chars, edited in `/account`; shown as a grey outlined tag right after the name on the profile (uppercase small, like the top-cut tag). Suggestions while typing from the distinct team names other users already use (datalist). No link to tournaments. |
| D11 | Everything is rendered server-side; a Stimulus controller does search, filters, sort, expand and the derived numbers from `data-*` attributes on the rows. Without JavaScript the full table shows with all rows and the server-computed totals. |
| D12 | Grey only: the band is `bg-surface-raised`, numbers `text-ink`, labels `text-muted` uppercase; the achievements box `border-line-2` on `bg-surface`; no accent except seat-1 highlight in the detail row. |

## 3. Data (`Profiles::History`)

`Row` gains: `games` (wins + losses + draws), `made_cut` (Boolean: a seating or an `Advance` in a `SingleEliminationRound` of that event), `cut_size` (`event.top_cut_size_or_suggested`, nil when 0), `commander` (`participation.commander_text`, nil when blank or a link), `organizer_name`, `format_line` (the About card's format label: "cEDH · pods of four" / "1v1 · best of 3"), `season` (the event's circuit name, nil without one), `round_seats` (Array of seat positions by Swiss round number, `[2, 1, 1, 2]`; `nil` for 1v1). All in a fixed number of queries (made_cut and round_seats come from two grouped queries over the participations' ids). Existing fields stay (`seats`, `decklist_visible`, `decklist`).

Server-side totals (`Profiles::Summary.call(rows)` → events, top_cuts, win_rate, conversion_rate, wins, top4, commanders `[[name, count], …]` top 4) render the initial numbers; the Stimulus controller recomputes the same figures from the visible rows.

Win rate = wins ÷ games over the filtered rows; nil → "–" when there are no games. Conversion rate = made_cut count ÷ events; "–" with no events. Both shown as whole percentages.

## 4. Markup

- Profile header: avatar, name + team tag, handle, country, Follow (unchanged, still disabled), bio.
- Band `[data-profile-summary]`: stats strip (4 cells, `data-stat="events|top_cuts|win_rate|conversion"`), achievements box (`data-ach="wins|top4|cuts"`), commanders list (`[data-commanders]`, 2 columns, `li` per commander with name, "n · x%" and the bar).
- Toolbar `[data-profile-tools]`: search input (`data-profile-events-target="search"`), year buttons (`data-year="all|2026|…"`), season select (`data-season`), count "n of N events".
- Table `[data-profile-events]`: `thead` with sortable `th[data-sort="date|name|position"]`; `tbody` rows `tr[data-event]` with `data-date`, `data-name`, `data-organizer`, `data-commander`, `data-format`, `data-year`, `data-season`, `data-position`, `data-participants`, `data-wins`, `data-losses`, `data-draws`, `data-cut` (1/0); each followed by its hidden detail `tr[data-event-detail]` (server-rendered, `hidden`), toggled by the "+" (`aria-controls`, `aria-expanded`, `[data-sign]` like `row_expander_controller`). "More" footer with the button.
- Empty states: no finished events → the existing "No finished events yet." card, no band, no toolbar. No rows after filtering → one `td` "No events match." row.
- All pieces use the existing M7 classes (`card`, `ctable`, `chip`, `button_classes(:secondary, size: :sm)`, `.field` for the search); the few new rules (band, achievements box, tag, toggle) go into the Tailwind stylesheet under a `/* profile */` block. Forbidden-colour grep stays 0.

## 5. Account form

`users.team` string, `validates length: { maximum: 30 }`, normalised `strip.presence`. Field "Team" after Country with hint "The group you test and play with. Shown next to your name." and a `datalist` of up to 50 distinct team names of other users (`User.where.not(team: nil).distinct.order(:team).limit(50)`), permitted in `AccountsController`. Anonymisation (`Accounts::Anonymize`) clears `team`.

## 6. Copy (en; pt-PT tu-form; es)

`profiles.stats.{events,top_cuts,win_rate,conversion_rate}` = "Events / Top cuts / Win rate / Conversion rate"; `profiles.achievements.{wins,top4,top_cuts}` = "Wins / Top 4 / Top cuts"; `profiles.commanders` = "Most played commanders"; `profiles.search_placeholder` = "Search events, organizers, commanders…"; `profiles.all_years` = "All"; `profiles.all_seasons` = "All seasons"; `profiles.count` = "%{shown} of %{total} events"; `profiles.show_all` = "Show all %{count} events"; `profiles.show_less` = "Show less"; `profiles.no_match` = "No events match."; `profiles.columns.{date,event,result,commander}`; `profiles.top_cut_tag` = "Top %{size}"; `profiles.detail.{record,win_rate,games,seats,seat_one,of_rounds,no_seats,round_seat}` = "Record / Win rate / %{count} games / Seats taken / Seat 1 / of %{count} rounds / 1v1 · no seats / R%{round} · seat %{seat}"; `accounts.show.team` label "Team", `accounts.show.team_hint`. pt: "Eventos / Top cuts / Taxa de vitória / Conversão", "Vitórias / Top 4 / Top cuts", "Comandantes mais jogados", "Procura eventos, organizadores, comandantes…", "Todos", "Todas as épocas", "%{shown} de %{total} eventos", "Ver todos os %{count} eventos", "Ver menos", "Nenhum evento corresponde.", "Registo / Taxa de vitória / %{count} jogos / Lugares ocupados / Lugar 1 / de %{count} rondas / 1v1 · sem lugares / R%{round} · lugar %{seat}", "Equipa", "O grupo com quem testas e jogas. Aparece ao lado do teu nome."

## 7. Out of scope

Follow (stays disabled), comments, team pages or team rankings, server-side pagination, changes to the events list the organizer sees.

## 8. Acceptance

1. A profile with 12 finished events across three years and two circuits shows the band with the right totals, the four achievements/commander numbers, the year buttons for those three years and the two seasons in the select; six rows and "Show all 12 events".
2. Typing a commander name hides the other rows and the band numbers change to the visible rows (system test).
3. The "+" opens the detail row with record, win rate, seats taken, seat-1 share and the per-round sequence; 1v1 rows say "1v1 · no seats".
4. A player who reached the top 16 of a Top-16 event shows "Top 16" after the event name and counts in Top cuts and Conversion rate; one who finished 1st also counts in Wins and Top 4.
5. The result cell is white; no accent on positions.
6. `/account` saves a team of 30 characters, rejects 31, suggests existing names; the profile shows the tag only when set; anonymised users lose it.
7. Without JavaScript the full table renders with the server-side totals (controller test asserts the rows and the band numbers).
8. Prosopite raises nothing on the profile (one history load, fixed query count).
