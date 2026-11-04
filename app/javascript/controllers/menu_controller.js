import { Controller } from "@hotwired/stimulus";

// Top bar on phones: the hamburger shows or hides the nav panel (links, language, account).
export default class extends Controller {
  static targets = ["panel", "button"];

  toggle() {
    const open = this.panelTarget.dataset.open !== "true";
    this.panelTarget.dataset.open = String(open);
    this.buttonTarget.setAttribute("aria-expanded", String(open));
  }
}
