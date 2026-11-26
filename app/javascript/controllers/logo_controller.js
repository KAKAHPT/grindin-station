import { Controller } from "@hotwired/stimulus";

// The landing's logo as a departures board: every few seconds the seven tiles flap to a word of the game, hold
// it, and flap back to the name. Each tile runs through a few letters on its way, one tile after the other.
// Nothing moves for a visitor who asked for reduced motion.
const NAME = "GRINDIN";
const WORDS = ["PAIRING", "SEATING", "TOP CUT", "PLAYING", "TRIGGER", "COUNTER", "WIN CON", "SHUFFLE", "CEDH PT",
  "FAIREST", "NONSTOP", "ROUND 1", "THE POD", "WINNING", "ON TIME"];
const EVERY_MS = 7000;
const HOLD_MS = 2600;
const FLAP_MS = 110;
const TILE_GAP_MS = 70;
const RUN = 3;
const ABC = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

export default class extends Controller {
  static targets = ["letter"];

  connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    this.turn = 0;
    this.timers = [];
    this.loop = setInterval(() => {
      this.spell(WORDS[this.turn++ % WORDS.length]);
      this.later(HOLD_MS, () => this.spell(NAME));
    }, EVERY_MS);
  }

  disconnect() {
    clearInterval(this.loop);
    this.timers?.forEach(clearTimeout);
    this.letterTargets.forEach((letter, index) => { letter.textContent = NAME[index]; });
  }

  spell(word) {
    this.letterTargets.forEach((letter, index) => {
      // The letters just before the target in the alphabet, then the target.
      const at = Math.max(ABC.indexOf(word[index]), RUN);
      const run = [...ABC.slice(at - RUN, at), word[index]];
      run.forEach((next, step) => this.later(index * TILE_GAP_MS + step * FLAP_MS, () => this.flap(letter, next)));
    });
  }

  // The letter folds into the cut line, changes, and unfolds.
  flap(letter, next) {
    letter.animate([{ transform: "scaleY(1)" }, { transform: "scaleY(0)" }], { duration: FLAP_MS / 2, easing: "ease-in" })
      .finished.then(() => {
        letter.textContent = next;
        letter.animate([{ transform: "scaleY(0)" }, { transform: "scaleY(1)" }], { duration: FLAP_MS / 2, easing: "ease-out" });
      }).catch(() => {});
  }

  later(ms, run) {
    this.timers.push(setTimeout(run, ms));
  }
}
