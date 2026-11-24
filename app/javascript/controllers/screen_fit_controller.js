import { Controller } from "@hotwired/stimulus"

// The TV screen is laid out once, on a fixed stage (1920x1080, or 1080x1920 for an upright window), and the
// whole stage is scaled to the window: nothing reflows, so nothing can overlap at any window size. The clock's
// font follows its number of characters ("42:17", "149:59") so it always fits its card.
export default class extends Controller {
  static targets = ["stage", "clock"]

  connect() {
    this.fit = this.fit.bind(this)
    window.addEventListener("resize", this.fit)
    document.addEventListener("turbo:morph", this.fit)
    this.fit()
  }

  disconnect() {
    window.removeEventListener("resize", this.fit)
    document.removeEventListener("turbo:morph", this.fit)
    this.observer?.disconnect()
  }

  clockTargetConnected(clock) {
    this.observer?.disconnect()
    this.observer = new MutationObserver(() => this.fitClock())
    this.observer.observe(clock, { childList: true, characterData: true, subtree: true })
    this.fitClock()
  }

  fit() {
    const upright = window.innerWidth < window.innerHeight * 0.8
    const [width, height] = upright ? [1080, 1920] : [1920, 1080]
    const scale = Math.min(window.innerWidth / width, window.innerHeight / height)
    const stage = this.stageTarget
    stage.dataset.upright = String(upright)
    stage.style.width = `${width}px`
    stage.style.height = `${height}px`
    stage.style.transform = `translate(-50%, -50%) scale(${scale})`
    this.fitClock()
  }

  // Digits are tabular: about 0.62em each. The card leaves the clock 620px (stage pixels) in both layouts.
  fitClock() {
    if (!this.hasClockTarget) return
    const timer = this.clockTarget.querySelector("[data-controller]")
    if (!timer) return
    const size = Math.min(210, Math.floor(620 / (0.62 * timer.textContent.trim().length)))
    if (this.clockTarget.style.fontSize !== `${size}px`) this.clockTarget.style.fontSize = `${size}px`
  }
}
