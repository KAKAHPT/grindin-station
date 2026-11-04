import { Controller } from "@hotwired/stimulus";

// Pairings search: hides the table cards without a player whose name contains the typed text.
// cards: the card selector (default the organizer round page's pod cards; public pairings pass [data-pairing-table]).
export default class extends Controller {
  static targets = ["input"];
  static values = { cards: { type: String, default: "[id^='pod_']" } };

  filter() {
    const q = this.inputTarget.value.trim().toLowerCase();
    document.querySelectorAll(this.cardsValue).forEach((card) => {
      const names = [...card.querySelectorAll("[data-name]")].map((el) => el.dataset.name.toLowerCase());
      card.hidden = q !== "" && !names.some((n) => n.includes(q));
    });
  }
}
