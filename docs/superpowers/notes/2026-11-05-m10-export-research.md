# M10 export research (checked 2026-11-04/05)

Caveat: web-search/fetch summaries only. Anything marked UNCONFIRMED was not found in a source.

## 1. Wizards EventLink
Source: https://wpn.wizards.com/en/news/definitive-guide-wizards-eventlink (Mar 2024 guide; nothing newer found for late 2026)
- **Import:** only documented import is a CSV *invite list* (Wizards Account emails or display names in column A; duplicates and emails with no account cause errors). No documented import of pairings/results/standings. No public API found. UNCONFIRMED that none exists.
- **Player ID:** Wizards Account email, Companion registration, or guest (first+last name only; one event; name deleted after 24h; guests count for tickets/prerelease allocation but not "engaged players"). DCI numbers not used.
- **Manual workflow order:** enrol players (Companion/event code/QR, Add Email, Add Guest, CSV invite) -> start -> pairings (Swiss, Single Elim, or "Player List Only") -> results per table (players via Companion, or organiser from pairings screen) -> Create Next Round -> Edit Scores Round X for fixes -> End Event (else auto-reports after 1 week). Standings viewable in app/Companion.
- **Commander/multiplayer:** guide says use **Player List Only** (no rounds/pairings, so no per-pod results are recorded; counts toward play metrics). Only 2HG has team support. Pods of 4 with per-pod win/draw are NOT supported as structured results. Wizards feedback post (Aug 2025, 3 votes, no response) complains Commander is unavailable for store reporting: https://feedback.wizards.com/forums/929932-companion-feedback/suggestions/50344161-commander-tournaments-unavailable-for-store-report
- **Third parties:** TopDeck "Export to Event Link" (Jul 2025, MTG only) pushes *player data* (not confirmed: pairings/results) into an existing/new EventLink event; matches by optional Wizards email, else TopDeck email, else guest. Re-export syncs without duplicates (except manually added players). https://topdeck.gg/blog/event-link-export-system-20250724
  Chrome extension "ChallengerTCG - MTG Fetcher" scrapes EventLink out (v3.1, Jan 2026): https://chromewebstore.google.com/detail/lofkbplpnbaefcnbldbpbnagllpaagin
- **Implication for us:** best export = (a) invite-list CSV, one column A of Wizards emails (fallback display names); (b) a printable sheet: final standings + per-round pod results for manual entry / judge records; for Commander, EventLink needs only the player list + End Event.

## 2. Melee (mtgmelee.com / melee.gg)
Source: https://help.melee.gg/docs/mass-data-importing/ (page ~700 days old)
- Player import CSV columns: required `Email, FirstName, LastName`; optional `MtgoScreenName` (spelled "MtgoScrenName" on the page), `Status`, `UserName`, `WizardsAccountDisplayName`. Wizard at Players > Import players; access restricted, must ask Melee team (contact@melee.gg); may involve per-player fee.
- Alternatives: Preregistrations import (grants access only, doesn't enrol), paste-emails dialog in Tournament Controller.
- Results/pairings import/export: page says nothing; UNCONFIRMED (ask Melee).

## 3. TopDeck.gg
- **Exports:** Rounds page Export = current round or standings as CSV (named event+date), follows pool filter; roster Export; community members table export. https://topdeck.gg/help/running-a-tournament . Column list NOT documented: download a real file to see headers.
- **Import pairings** CSV: header row, then one row per table: table number + each player's name (Carde.io export works as-is).
- WER-style XML player export (Topdecked, different product): `players-{event}-{ID}.xml`, columns not documented: https://www.topdecked.com/articles/documentation/export-download-events-registered-players-wer
- **JSON API** (no CSV): https://topdeck.gg/docs/tournaments-v2 . standings: `standing,name,id,leader,archetype,decklist,points,winRate,opponentWinRate` (+wins/losses/draws/byes via `columns`). rounds: `round`, `tables[]{table, players[]{name,id,...}, winner (name | "Draw" for 1v1 | null for pod draw/unfinished), winner_id, status(Completed/Active/Pending/Bye), points (points pods)}`. Write of results not available (see project memory).
- **Pairing names (Commander)** https://topdeck.gg/help/running-commander-tournament :
  - Swiss pods (recommended): "builds pods of players on similar records" (converges toward circular pairing as rounds progress, per search summary; mechanics not documented)
  - True Swiss: standard Swiss each round (undefined on page)
  - Power pods: "builds pods top-down from the standings" (recommended for final rounds)
  - Bubble pods: seats in standing order (not defined on page)
  - Random pods: ignores records
  - Bye Mode: "Allow Byes (No 3 Person Pods)", "Pair Low/High Standings into 3 Pod / 5 Pod"
  - Pods seat 4 by default; Draw Mode: All or Nothing / Custom Percent / Equal Distribution; Make cut by Points or Rank; pod cut sizes Top 4,7,10,13,16,40,64.
- **Last round / cut-aware:** NOT documented. Only hint: Power pairing "useful for a final round". No "cut-aware pairing" term found. Do not claim TopDeck has a no-spread last-round rule.

## 4. Community CSV conventions
- Nothing authoritative found for EventLink/Companion exports (EventLink has no general export; print pairings only), Bracketeer, or Challonge column schemas (not searched in depth: UNCONFIRMED).
- Reasonable interoperable choices: (1) Melee-style player CSV `Email,FirstName,LastName,WizardsAccountDisplayName`; (2) EventLink invite CSV, col A = email; (3) TopDeck import-pairings shape: header + `Table,Player1,Player2,Player3,Player4`; (4) standings CSV mirroring TopDeck API names: `standing,name,id,points,winRate,opponentWinRate` plus `wins,draws,byes`; (5) rounds long-format: `round,table,player,seat,result(win/draw/loss),points`.
