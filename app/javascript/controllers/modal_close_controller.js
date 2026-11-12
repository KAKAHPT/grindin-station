import { Controller } from "@hotwired/stimulus";

// Cancel inside the sign-in modal: empties the modal frame. A link would load its page into the frame, and a
// page without that frame leaves Turbo's "Content missing" behind and an error in the console.
export default class extends Controller {
  close() {
    const frame = this.element.closest("turbo-frame");
    frame.removeAttribute("src");
    frame.innerHTML = "";
  }
}
