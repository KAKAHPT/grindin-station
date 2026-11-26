import { Controller } from "@hotwired/stimulus";

// Landing, featured tickets in motion: each ticket comes in from the top right, small and soft, rests on the
// right, moves to the front (larger, with its details open underneath), rests on the left and leaves.
// Hovering the row pauses it. Nothing moves with fewer than three tickets, on a row too narrow for three
// (phones keep the swipe rail), or for a visitor who asked for reduced motion.
const STEP_MS = 4600;
const MIN_ITEMS = 6;

export default class extends Controller {
  static targets = ["track"];

  connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    this.track = this.trackTarget;
    this.items = [...this.track.children];
    if (this.items.length < 3 || this.items[0].offsetWidth * 2 > this.track.clientWidth) return;
    while (this.items.length < MIN_ITEMS) {
      for (const item of [...this.track.children]) {
        const copy = item.cloneNode(true);
        copy.setAttribute("aria-hidden", "true");
        copy.querySelectorAll("a, button").forEach((el) => el.setAttribute("tabindex", "-1"));
        this.track.appendChild(copy);
        this.items.push(copy);
      }
    }
    this.layout = this.layout.bind(this);
    this.pause = () => this.animations.forEach((a) => a.pause());
    this.play = () => this.animations.forEach((a) => a.play());
    this.track.addEventListener("mouseenter", this.pause);
    this.track.addEventListener("mouseleave", this.play);
    window.addEventListener("resize", this.layout);
    this.layout();
  }

  disconnect() {
    this.animations?.forEach((a) => a.cancel());
    window.removeEventListener("resize", this.layout);
  }

  layout() {
    this.animations?.forEach((a) => a.cancel());
    const track = this.track;
    track.classList.add("lp-flow");
    const W = track.clientWidth;
    const w = this.items[0].offsetWidth;
    const H = Math.max(...this.items.map((item) => item.offsetHeight));
    const n = this.items.length;
    const duration = n * STEP_MS;
    // Half a step in from the start, so the page opens with a ticket at the front and its details showing.
    const timing = (index) => ({ duration, iterations: Infinity, delay: -((index + 0.5) * duration) / n, easing: "linear" });
    track.style.height = `${H * 1.22 + 250}px`;

    const step = 1 / n;
    const move = 0.3 * step;
    const DIM = { boxShadow: "0 14px 34px -18px #000, 0 0 0 0 rgb(255 255 255 / 0)", borderColor: "var(--color-line)" };
    const LIT = { boxShadow: "0 24px 60px -20px #000, 0 0 54px 4px rgb(250 204 21 / 0.34)", borderColor: "rgb(250 204 21 / 0.85)" };
    const at = (x, y, scale, opacity, blur = 0, zIndex = 0) => ({ transform: `translate(${x}px, ${y}px) scale(${scale})`, opacity, filter: `blur(${blur}px)`, zIndex, width: `${w}px`, ...DIM });
    const right = W - w;
    const wide = w * 1.3;
    // The ticket's own layout is pinned to these two widths, so nothing inside moves while it widens.
    track.style.setProperty("--ftw", `${w}px`);
    track.style.setProperty("--ftwide", `${wide}px`);
    const push = w * 0.22;
    const far = at(W * 1.1, -1.3 * H, 0.4, 0, 6);
    const onRight = at(right + w * 0.04, 0, 0.88, 0.55);
    const rightOut = at(right + w * 0.04 + push, 0, 0.88, 0.45);
    const front = { ...at(right / 2, 0, 1.22, 1, 0, 2), ...LIT };
    const frontWide = { ...front, transform: `translate(${(W - wide) / 2}px, 0px) scale(1.22)`, width: `${wide}px` };
    const onLeft = at(-w * 0.04, 0, 0.88, 0.55);
    const leftOut = at(-w * 0.04 - push, 0, 0.88, 0.45);
    const gone = at(-w * 0.8, 0.1 * H, 0.6, 0, 4);
    const ease = "cubic-bezier(.4,0,.2,1)";
    // The front ticket widens once it has landed and narrows before it leaves; the two beside it step aside
    // for exactly that long (every ticket is one step apart, so the same moments of each step).
    const widen = [move, 1.7 * move];
    const narrow = [step - 0.5 * move, step];
    const ticket = [
      { ...far, offset: 0, easing: "cubic-bezier(.2,.7,.2,1)" },
      { ...at(W * 0.98, -0.6 * H, 0.6, 0.4, 3), offset: move * 0.45, easing: "cubic-bezier(.2,.7,.2,1)" },
      { ...onRight, offset: widen[0], easing: ease },
      { ...rightOut, offset: widen[1] },
      { ...rightOut, offset: narrow[0], easing: ease },
      { ...onRight, offset: narrow[1], easing: ease },
      { ...front, offset: step + widen[0], easing: ease },
      { ...frontWide, offset: step + widen[1] },
      { ...frontWide, offset: step + narrow[0], easing: ease },
      { ...front, offset: step + narrow[1], easing: ease },
      { ...onLeft, offset: 2 * step + widen[0], easing: ease },
      { ...leftOut, offset: 2 * step + widen[1] },
      { ...leftOut, offset: 2 * step + narrow[0], easing: ease },
      { ...onLeft, offset: 2 * step + narrow[1], easing: "cubic-bezier(.4,0,1,1)" },
      { ...gone, offset: 3 * step + move },
      { ...far, offset: 1 },
    ];
    const shut = { maxHeight: "0px", opacity: 0 };
    const open = { maxHeight: "220px", opacity: 1 };
    const details = [
      { ...shut, offset: 0 },
      { ...shut, offset: step + move * 0.7 },
      { ...open, offset: step + move * 1.6 },
      { ...open, offset: 2 * step - move * 0.9 },
      { ...shut, offset: 2 * step - move * 0.3 },
      { ...shut, offset: 1 },
    ];
    this.animations = this.items.flatMap((item, index) => {
      const panel = item.querySelector("[data-ft-more]");
      return [item.animate(ticket, timing(index)), panel?.animate(details, timing(index))].filter(Boolean);
    });
  }
}
