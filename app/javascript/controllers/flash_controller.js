import { Controller } from "@hotwired/stimulus"

// A success notice leaves on its own; alerts stay until closed.
export default class extends Controller {
  static values = { after: { type: Number, default: 5000 } }

  connect() {
    this.timeout = setTimeout(() => this.element.remove(), this.afterValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
