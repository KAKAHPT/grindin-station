import { Controller } from "@hotwired/stimulus"

// The TV screen's tables come in blocks (pages) that take turns: one shows, the dots mark which. A live morph
// refresh brings the server markup back (first page shown), so the current page is re-applied after it.
export default class extends Controller {
  static targets = ["page", "dot", "label"]
  static values = { seconds: { type: Number, default: 12 } }

  connect() {
    this.index = 0
    this.reapply = () => this.show()
    document.addEventListener("turbo:morph", this.reapply)
    this.show()
    this.interval = setInterval(() => this.next(), this.secondsValue * 1000)
  }

  disconnect() {
    clearInterval(this.interval)
    document.removeEventListener("turbo:morph", this.reapply)
  }

  next() {
    this.index += 1
    this.show()
  }

  show() {
    const count = this.pageTargets.length
    if (count === 0) return
    this.index %= count
    this.pageTargets.forEach((page, i) => { page.hidden = i !== this.index })
    this.dotTargets.forEach((dot, i) => dot.toggleAttribute("data-on", i === this.index))
    if (this.hasLabelTarget) this.labelTarget.textContent = this.pageTargets[this.index].dataset.label
  }
}
