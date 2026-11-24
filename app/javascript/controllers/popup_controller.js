import { Controller } from "@hotwired/stimulus"

// Opens the link in its own window (the organizer's Open clock): one to drag to a second monitor or a TV.
// A blocked popup falls back to the link's own target.
export default class extends Controller {
  open(event) {
    const opened = window.open(this.element.href, this.element.target || "_blank", "popup,width=1280,height=720")
    if (opened) event.preventDefault()
  }
}
