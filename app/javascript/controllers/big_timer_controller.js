import { Controller } from "@hotwired/stimulus";

// Big-screen countdown: computed from the client clock, keeps counting past zero as -mm:ss in red.
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
    const abs = Math.abs(remaining);
    const mm = String(Math.floor(abs / 60)).padStart(2, "0");
    const ss = String(abs % 60).padStart(2, "0");
    this.element.textContent = `${remaining < 0 ? "-" : ""}${mm}:${ss}`;
    this.element.style.color = remaining < 0 ? "#f87171" : "";
  }
}
