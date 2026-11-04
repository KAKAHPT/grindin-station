import { Controller } from "@hotwired/stimulus";

// Big-screen countdown: computed from the client clock, stops at 00:00 in red once time is up.
export default class extends Controller {
  static values = { startedAt: String, minutes: Number };

  connect() {
    this.startedAtMs = new Date(this.startedAtValue).getTime();
    this.tick();
    this.interval = setInterval(() => this.tick(), 1000);
  }

  disconnect() {
    clearInterval(this.interval);
  }

  tick() {
    const elapsed = Math.floor((Date.now() - this.startedAtMs) / 1000);
    const remaining = this.minutesValue * 60 - elapsed;
    const clamped = Math.max(remaining, 0);
    const mm = String(Math.floor(clamped / 60)).padStart(2, "0");
    const ss = String(clamped % 60).padStart(2, "0");
    this.element.textContent = `${mm}:${ss}`;
    this.element.style.color = remaining < 0 ? "#f87171" : "";
  }
}
