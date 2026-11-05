import { Controller } from "@hotwired/stimulus"

// Submits the field's form when its value changes (the selects of shared/_filter_bar).
export default class extends Controller {
  submit() {
    this.element.form.requestSubmit()
  }
}
