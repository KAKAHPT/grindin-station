import { Controller } from "@hotwired/stimulus";

// A row of arts where one changes every few seconds, each card in turn: the card fades out, takes an art not on
// show, and fades back in. Nothing changes for a visitor who asked for reduced motion.
const EVERY_MS = 3500;
const FADE_MS = 700;

export default class extends Controller {
  static targets = ["card"];
  static values = { urls: Array };

  connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    this.turn = 0;
    this.timer = setInterval(() => this.swap(), EVERY_MS);
  }

  disconnect() {
    clearInterval(this.timer);
  }

  swap() {
    // From the right, where the row is clearest, towards the text.
    const card = this.cardTargets.at(-1 - (this.turn % this.cardTargets.length));
    this.turn += 1;
    const shown = this.cardTargets.map((img) => new URL(img.src).pathname);
    const free = this.urlsValue.filter((url) => !shown.includes(url));
    if (free.length === 0) return;
    const next = new Image();
    next.onload = () => {
      card.classList.add("evb-out");
      setTimeout(() => {
        card.src = next.src;
        card.classList.remove("evb-out");
      }, FADE_MS);
    };
    next.src = free[Math.floor(Math.random() * free.length)];
  }
}
