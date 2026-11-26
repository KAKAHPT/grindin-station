import { Controller } from "@hotwired/stimulus";

// Landing, featured tickets in motion: each ticket comes in from the top right, small and soft, rests on the
// right, moves to the front (larger, with its details open underneath), rests on the left and leaves.
// Hovering the row pauses it. Nothing moves with fewer than three tickets, on a row too narrow for three
// (phones keep the swipe rail), or for a visitor who asked for reduced motion.
const STEP_MS = 6200;
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
    const wide = w * 1.3;
    // The ticket's own layout is pinned to these two widths, so nothing inside moves while it widens.
    track.style.setProperty("--ftw", `${w}px`);
    track.style.setProperty("--ftwide", `${wide}px`);
    const H = Math.max(...this.items.map((item) => item.offsetHeight));
    const n = this.items.length;
    const duration = n * STEP_MS;
    // Half a step in from the start, so the page opens with a ticket at the front and its details showing.
    const timing = (index) => ({ duration, iterations: Infinity, delay: -((index + 0.5) * duration) / n, easing: "linear" });
    // Room for the lifted ticket with its details open, and no more: the tallest details decide.
    const panels = this.items.map((item) => item.querySelector("[data-ft-more]")).filter(Boolean);
    const P = Math.max(0, ...panels.map((panel) => panel.scrollHeight));
    track.style.height = `${(H + P) * 1.38 - 8}px`;

    const step = 1 / n;
    const move = 0.22 * step;
    const DIM = { boxShadow: "0 14px 34px -18px #000, 0 0 0 0 rgb(255 255 255 / 0)", borderColor: "var(--color-line)" };
    // The light of the front ticket: a warm white edge and halo.
    const edge = "255 244 214";
    const halo = "255 236 190";
    const LIT = { boxShadow: `0 24px 60px -20px #000, 0 0 28px 0 rgb(${halo} / 0.12)`, borderColor: `rgb(${edge} / 0.45)` };
    // Lifted: the ticket leaves the page, with a deep shadow under it and the full light around it.
    const LIFTED = { boxShadow: `0 70px 90px -34px #000, 0 0 44px 2px rgb(${halo} / 0.2)`, borderColor: `rgb(${edge} / 0.7)` };
    const place = (x, y, scale, tilt = 0) => `perspective(900px) translate(${x}px, ${y}px) rotateX(${tilt}deg) scale(${scale})`;
    const at = (x, y, scale, opacity, blur = 0, zIndex = 0) => ({ transform: place(x, y, scale), opacity, filter: `blur(${blur}px)`, zIndex, width: `${w}px`, ...DIM });
    const right = W - w;
    const push = w * 0.34;
    const far = at(W * 1.1, -1.3 * H, 0.4, 0, 6);
    const onRight = at(right + w * 0.04, 0, 0.88, 0.55);
    const rightOut = at(right + w * 0.04 + push, 0, 0.78, 0.32, 1.5);
    // Landed: flat on the page, leaning back a little, before it takes off.
    const front = { ...at(right / 2, 0, 1, 1, 0, 2), ...LIT, transform: place(right / 2, 0, 1, 16) };
    const frontWide = { ...front, ...LIFTED, transform: place((W - wide) / 2, -22, 1.36), width: `${wide}px` };
    const frontFloat = { ...frontWide, transform: place((W - wide) / 2, -32, 1.38) };
    const onLeft = at(-w * 0.04, 0, 0.88, 0.55);
    const leftOut = at(-w * 0.04 - push, 0, 0.78, 0.32, 1.5);
    const gone = at(-w * 0.8, 0.1 * H, 0.6, 0, 4);
    const ease = "cubic-bezier(.4,0,.2,1)";
    // The front ticket widens once it has landed and narrows before it leaves; the two beside it step aside
    // for exactly that long (every ticket is one step apart, so the same moments of each step).
    const widen = [move, 1.9 * move];
    const narrow = [step - 0.5 * move, step];
    const ticket = [
      { ...far, offset: 0, easing: "cubic-bezier(.2,.7,.2,1)" },
      { ...at(W * 0.98, -0.6 * H, 0.6, 0.4, 3), offset: move * 0.45, easing: "cubic-bezier(.2,.7,.2,1)" },
      { ...onRight, offset: widen[0], easing: ease },
      { ...rightOut, offset: widen[1] },
      { ...rightOut, offset: narrow[0], easing: ease },
      { ...onRight, offset: narrow[1], easing: ease },
      { ...front, offset: step + widen[0], easing: "cubic-bezier(.3,1.5,.5,1)" },
      { ...frontWide, offset: step + widen[1], easing: "ease-in-out" },
      { ...frontFloat, offset: step + (widen[1] + narrow[0]) / 2, easing: "ease-in-out" },
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
    const open = { maxHeight: `${P}px`, opacity: 1 };
    const details = [
      { ...shut, offset: 0 },
      { ...shut, offset: step + move * 0.7 },
      { ...open, offset: step + move * 1.6 },
      { ...open, offset: 2 * step - move * 0.9 },
      { ...shut, offset: 2 * step - move * 0.3 },
      { ...shut, offset: 1 },
    ];
    // A streak of light crosses the ticket as it takes off.
    const still = { transform: "translateX(-140%) skewX(-18deg)", opacity: 0 };
    const shine = [
      { ...still, offset: 0 },
      { ...still, opacity: 1, offset: step + widen[0] },
      { transform: "translateX(260%) skewX(-18deg)", opacity: 1, offset: step + widen[1] },
      { ...still, offset: step + widen[1] + 0.001 },
      { ...still, offset: 1 },
    ];
    this.animations = this.items.flatMap((item, index) => {
      const panel = item.querySelector("[data-ft-more]");
      return [
        item.animate(ticket, timing(index)),
        item.animate(shine, { ...timing(index), pseudoElement: "::after" }),
        panel?.animate(details, timing(index)),
      ].filter(Boolean);
    });
  }
}
