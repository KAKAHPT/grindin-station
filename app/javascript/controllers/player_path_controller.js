import { Controller } from "@hotwired/stimulus"

// The final standings' player dialog: a name loads that player's path into the frame. The dialog opens as soon as
// the request starts (not when it renders, which could reopen a dialog the reader has just closed) and is
// emptied on close, so the next player never shows over the previous one.
export default class extends Controller {
  static targets = ["dialog", "frame"]

  open() {
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  clear() {
    this.frameTarget.innerHTML = ""
    this.frameTarget.removeAttribute("src")
  }
}
