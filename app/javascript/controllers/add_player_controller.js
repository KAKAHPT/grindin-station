import { Controller } from "@hotwired/stimulus";

// The roster's Add player dialog: three tabs (by e-mail, by name, manually). The e-mail and name tabs look accounts
// up as the organizer types (urlValue, JSON rows from Registrations::PlayerSearch) and picking one fills the hidden
// player_id; the fields of the hidden tabs are disabled so only the active tab is submitted.
export default class extends Controller {
  static targets = ["tab", "panel", "input", "results", "playerId", "chosen", "mode"];
  static values = { url: String, mode: String, inEvent: String, empty: String };

  connect() {
    this.show({ params: { mode: this.modeValue } });
  }

  show(event) {
    const mode = event.params?.mode || event.currentTarget?.dataset.mode;
    this.modeValue = mode;
    this.modeTarget.value = mode;
    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.mode === mode;
      tab.setAttribute("aria-selected", String(active));
      tab.classList.toggle("segment-active", active);
      tab.classList.toggle("text-muted", !active);
    });
    this.panelTargets.forEach((panel) => {
      const active = panel.dataset.mode === mode;
      panel.hidden = !active;
      panel.querySelectorAll("input, textarea").forEach((field) => { field.disabled = !active; });
    });
    if (mode === "manual") this.clearPick();
  }

  search(event) {
    const input = event.currentTarget;
    this.clearPick();
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.fetch(input), 250);
  }

  async fetch(input) {
    const results = this.resultsFor(input);
    const text = input.value.trim();
    if (text.length < 2) return this.hide(results);

    const url = `${this.urlValue}?mode=${this.modeValue}&q=${encodeURIComponent(text)}`;
    const response = await fetch(url, { headers: { Accept: "application/json" } });
    if (!response.ok) return this.hide(results);

    const rows = await response.json();
    if (input.value.trim() !== text) return;
    results.innerHTML = rows.length ? rows.map((row) => this.item(row)).join("") : `<li class="ap-empty">${this.emptyValue}</li>`;
    results.hidden = false;
  }

  item(row) {
    const name = this.escape(row.name);
    const email = this.escape(row.email);
    const note = row.in_event ? `<em>${this.inEventValue}</em>` : "";
    const disabled = row.in_event ? "disabled" : "";
    return `<li><button type="button" ${disabled} data-action="add-player#pick" data-player-id="${row.player_id}"
      data-name="${name}" data-email="${email}"><b>${name}</b><span>${email}</span>${note}</button></li>`;
  }

  pick(event) {
    const { playerId, name, email } = event.currentTarget.dataset;
    const panel = event.currentTarget.closest("[data-add-player-target='panel']");
    const input = panel.querySelector("[data-add-player-target='input']");
    this.playerIdTarget.value = playerId;
    input.value = this.modeValue === "email" ? email : name;
    this.hide(this.resultsFor(input));
    if (this.hasChosenTarget) {
      this.chosenTarget.textContent = `${name} · ${email}`;
      this.chosenTarget.hidden = false;
    }
  }

  clearPick() {
    this.playerIdTarget.value = "";
    if (this.hasChosenTarget) this.chosenTarget.hidden = true;
  }

  resultsFor(input) {
    return input.closest("[data-add-player-target='panel']").querySelector("[data-add-player-target='results']");
  }

  hide(results) {
    results.hidden = true;
    results.innerHTML = "";
  }

  escape(text) {
    return String(text ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  }
}
