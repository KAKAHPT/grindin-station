import { Controller } from "@hotwired/stimulus";

// Top bar on phones: the hamburger shows or hides the nav panel (links, language, account).
// The open state belongs to the client: a Turbo morph refresh (round page broadcasts) keeps the
// panel's data-open and the button's aria-expanded instead of resetting them to the server's "false".
export default class extends Controller {
  static targets = ["panel", "button"];

  connect() {
    this.keepState = (event) => {
      const { attributeName } = event.detail;
      const owned = (event.target === this.panelTarget && attributeName === "data-open") ||
        (event.target === this.buttonTarget && attributeName === "aria-expanded");
      if (owned) event.preventDefault();
    };
    this.element.addEventListener("turbo:before-morph-attribute", this.keepState);
  }

  disconnect() {
    this.element.removeEventListener("turbo:before-morph-attribute", this.keepState);
  }

  toggle() {
    const open = this.panelTarget.dataset.open !== "true";
    this.panelTarget.dataset.open = String(open);
    this.buttonTarget.setAttribute("aria-expanded", String(open));
  }
}
