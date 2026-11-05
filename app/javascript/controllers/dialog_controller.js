import { Controller } from "@hotwired/stimulus"

// Opens and closes a <dialog> (the /rankings "How is it calculated?" modals). Escape closes it natively;
// a click on the backdrop (the dialog element itself, outside its content) closes it too.
export default class extends Controller {
  static targets = ["dialog"]

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
