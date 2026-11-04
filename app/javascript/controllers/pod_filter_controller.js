import { Controller } from "@hotwired/stimulus";

// Round page search: hides the pod cards without a player whose name contains the typed text.
export default class extends Controller {
  static targets = ["input"];

  filter() {
    const q = this.inputTarget.value.trim().toLowerCase();
    document.querySelectorAll("[id^='pod_']").forEach((card) => {
      const names = [...card.querySelectorAll("[data-name]")].map((el) => el.dataset.name.toLowerCase());
      card.hidden = q !== "" && !names.some((n) => n.includes(q));
    });
  }
}
