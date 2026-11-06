import { Controller } from "@hotwired/stimulus";

// Tournament form (New tournament, Settings): the public event page rendered beside the form from the values
// typed so far, reloaded on each change (debounced). Files (the cover) cannot travel in a URL and are left out.
const SKIPPED = ["_method", "authenticity_token", "button", "commit"];
const DELAY_MS = 400;

export default class extends Controller {
  static targets = ["form", "frame"];
  static values = { url: String };

  connect() {
    this.refresh = this.refresh.bind(this);
    this.formTarget.addEventListener("input", this.refresh);
    this.formTarget.addEventListener("change", this.refresh);
    this.load();
  }

  disconnect() {
    clearTimeout(this.timer);
    this.formTarget.removeEventListener("input", this.refresh);
    this.formTarget.removeEventListener("change", this.refresh);
  }

  refresh() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.load(), DELAY_MS);
  }

  load() {
    const url = new URL(this.urlValue, window.location.origin);
    for (const [name, value] of new FormData(this.formTarget)) {
      if (typeof value === "string" && !SKIPPED.includes(name)) url.searchParams.append(name, value);
    }
    this.frameTarget.src = url.toString();
  }
}
