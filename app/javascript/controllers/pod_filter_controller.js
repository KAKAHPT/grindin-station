import { Controller } from "@hotwired/stimulus";

// Pairings search: hides the table cards without a player whose name contains the typed text.
// cards: the card selector (default the organizer round page's pod cards; public pairings pass [data-pairing-table]).
// A live morph refresh puts the cards back as the server sent them: the filter runs again on turbo:morph
// (the public search input is data-turbo-permanent, so its text survives the morph).
export default class extends Controller {
  static targets = ["input"];
  static values = { cards: { type: String, default: "[id^='pod_']" } };

  connect() {
    this.filter = this.filter.bind(this);
    document.addEventListener("turbo:morph", this.filter);
  }

  disconnect() {
    document.removeEventListener("turbo:morph", this.filter);
  }

  filter() {
    // A morph that removes this controller's element fires turbo:morph before Stimulus disconnects it.
    if (!this.hasInputTarget) return;

    const q = this.inputTarget.value.trim().toLowerCase();
    document.querySelectorAll(this.cardsValue).forEach((card) => {
      const names = [...card.querySelectorAll("[data-name]")].map((el) => el.dataset.name.toLowerCase());
      card.hidden = q !== "" && !names.some((n) => n.includes(q));
    });
  }
}
