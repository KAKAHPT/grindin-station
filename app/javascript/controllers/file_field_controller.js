import { Controller } from "@hotwired/stimulus"

// Shows the chosen file's name in shared/_file_field (the native input is invisible over the box).
export default class extends Controller {
  static targets = ["name"]

  connect() {
    this.show()
  }

  show() {
    const file = this.element.querySelector("input[type=file]").files[0]
    this.nameTarget.textContent = file ? file.name : this.nameTarget.dataset.empty
  }
}
