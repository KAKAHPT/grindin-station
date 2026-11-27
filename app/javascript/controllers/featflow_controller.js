import { Controller } from "@hotwired/stimulus";

// Landing, featured tickets in motion. With three or more, each ticket comes in from the top right, small and
// soft, rests on the right, moves to the front (larger, lit, with its details open and its actions under it),
// rests on the left and leaves. One or two tickets stay at the front, side by side, floating gently.
// Hovering the row pauses it. Nothing moves on a row too narrow for three (phones keep the swipe rail) or, with
// three or more, for a visitor who asked for reduced motion; one or two then hold the front without floating.
const STEP_MS = 6200;
const MIN_ITEMS = 6;
const FRONT_SCALE = 1.3;
const PAIR_SCALE = 1.15;
const PAIR_GAP = 48;
// The light of the front ticket: a warm white edge and halo.
const EDGE = "255 244 214";
const HALO = "255 236 190";
const DIM = { boxShadow: "0 14px 34px -18px #000, 0 0 0 0 rgb(255 255 255 / 0)", borderColor: "var(--color-line)" };
const LIT = { boxShadow: `0 24px 60px -20px #000, 0 0 28px 0 rgb(${HALO} / 0.12)`, borderColor: `rgb(${EDGE} / 0.45)` };
// Lifted: the ticket leaves the page, with a deep shadow under it and the full light around it.
const LIFTED = { boxShadow: `0 60px 80px -34px #000, 0 0 44px 2px rgb(${HALO} / 0.2)`, borderColor: `rgb(${EDGE} / 0.7)` };
const place = (x, y, scale, tilt = 0) => `perspective(900px) translate(${x}px, ${y}px) rotateX(${tilt}deg) scale(${scale})`;

export default class extends Controller {
  static targets = ["track"];

  connect() {
    this.track = this.trackTarget;
    this.items = [...this.track.children];
    this.still = this.items.length < 3;
    if (this.items[0].offsetWidth * 2 > this.track.clientWidth) return;
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (!this.still && this.reduced) return;
    while (!this.still && this.items.length < MIN_ITEMS) {
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
    this.track.classList.add("lp-flow");
    const parts = this.items.map((item) => ({
      item,
      box: item.querySelector(".lp-ft"),
      panel: item.querySelector("[data-ft-more]"),
      acts: item.querySelector("[data-ft-acts]"),
    }));
    // Tickets standing at the front were placed by hand: back to their resting size before measuring again.
    if (this.still) parts.flatMap((part) => Object.values(part)).forEach((el) => el.removeAttribute("style"));
    const size = {
      W: this.track.clientWidth,
      w: this.items[0].offsetWidth,
      H: Math.max(...this.items.map((item) => item.offsetHeight)),
      // Room for the lifted ticket with its details open, and no more: the tallest details decide.
      P: Math.max(0, ...parts.map((part) => part.panel.scrollHeight)),
    };
    const scale = this.items.length === 2 ? PAIR_SCALE : FRONT_SCALE;
    this.track.style.height = `${(size.H + size.P) * scale + 10}px`;
    this.animations = this.still ? this.stand(parts, size, scale) : this.flow(parts, size);
  }

  // One or two tickets: at the front, lit and open, floating a little (out of step with each other).
  stand(parts, { W, w, P }, scale) {
    const each = w * scale + PAIR_GAP;
    const first = (W - parts.length * each + PAIR_GAP) / 2 + (w * scale - w) / 2;
    return parts.flatMap(({ item, box, panel, acts }, index) => {
      const x = first + index * each;
      Object.assign(item.style, { transform: place(x, 0, scale), zIndex: 2 });
      Object.assign(box.style, LIFTED);
      Object.assign(panel.style, { maxHeight: `${P}px`, height: `${P}px`, opacity: 1 });
      Object.assign(acts.style, { visibility: "visible", opacity: 1 });
      if (this.reduced) return [];
      const float = { duration: STEP_MS / 2, iterations: Infinity, direction: "alternate", easing: "ease-in-out" };
      return [item.animate([{ transform: place(x, 0, scale) }, { transform: place(x, -10, scale) }], { ...float, delay: (-index * STEP_MS) / 4 })];
    });
  }

  flow(parts, { W, w, H, P }) {
    const n = parts.length;
    const duration = n * STEP_MS;
    // Half a step in from the start, so the page opens with a ticket at the front and its details showing.
    const timing = (index) => ({ duration, iterations: Infinity, delay: -((index + 0.5) * duration) / n, easing: "linear" });
    const step = 1 / n;
    const move = 0.22 * step;
    const at = (x, y, scale, opacity, blur = 0, zIndex = 0) => ({ transform: place(x, y, scale), opacity, filter: `blur(${blur}px)`, zIndex });
    const right = W - w;
    const push = w * 0.14;
    const far = at(W * 1.1, -0.8 * H, 0.4, 0, 6);
    const onRight = at(right + w * 0.04, 0, 0.88, 0.55);
    const rightOut = at(right + w * 0.04 + push, 0, 0.8, 0.36, 1);
    // Landed: flat on the page, leaning back a little, before it takes off.
    const front = { ...at(right / 2, 0, 1, 1, 0, 2), transform: place(right / 2, 0, 1, 16) };
    const lifted = at(right / 2, 0, FRONT_SCALE, 1, 0, 2);
    const floated = at(right / 2, -10, FRONT_SCALE + 0.02, 1, 0, 2);
    const onLeft = at(-w * 0.04, 0, 0.88, 0.55);
    const leftOut = at(-w * 0.04 - push, 0, 0.8, 0.36, 1);
    const gone = at(-w * 0.8, 0.1 * H, 0.6, 0, 4);
    const ease = "cubic-bezier(.4,0,.2,1)";
    const drop = "cubic-bezier(.2,.7,.2,1)";
    // The front ticket grows once it has landed and shrinks before it leaves; the two beside it step aside
    // for exactly that long (every ticket is one step apart, so the same moments of each step).
    const widen = [move, 1.9 * move];
    const narrow = [step - 0.5 * move, step];
    // offset, where the ticket is, the light on its box, easing to the next row
    const rows = [
      [0, far, DIM, drop],
      [move * 0.45, at(W * 0.98, -0.4 * H, 0.6, 0.4, 3), DIM, drop],
      [widen[0], onRight, DIM, ease],
      [widen[1], rightOut, DIM],
      [narrow[0], rightOut, DIM, ease],
      [narrow[1], onRight, DIM, ease],
      [step + widen[0], front, LIT, "cubic-bezier(.3,1.5,.5,1)"],
      [step + widen[1], lifted, LIFTED, "ease-in-out"],
      [step + (widen[1] + narrow[0]) / 2, floated, LIFTED, "ease-in-out"],
      [step + narrow[0], lifted, LIFTED, ease],
      [step + narrow[1], front, LIT, ease],
      [2 * step + widen[0], onLeft, DIM, ease],
      [2 * step + widen[1], leftOut, DIM],
      [2 * step + narrow[0], leftOut, DIM, ease],
      [2 * step + narrow[1], onLeft, DIM, "cubic-bezier(.4,0,1,1)"],
      [3 * step + move, gone, DIM],
      [1, far, DIM],
    ];
    const ticket = rows.map(([offset, pose, , easing]) => ({ ...pose, offset, ...(easing && { easing }) }));
    const light = rows.map(([offset, , glow, easing]) => ({ ...glow, offset, ...(easing && { easing }) }));
    // The details and the actions open while the ticket is at the front.
    const opening = [0, step + move * 0.7, step + move * 1.6, 2 * step - move * 0.9, 2 * step - move * 0.3, 1];
    const during = (shut, open) => [shut, shut, open, open, shut, shut].map((frame, index) => ({ ...frame, offset: opening[index] }));
    const details = during({ maxHeight: "0px", opacity: 0 }, { maxHeight: `${P}px`, opacity: 1 });
    const actions = during({ visibility: "hidden", opacity: 0 }, { visibility: "visible", opacity: 1 });
    // A streak of light crosses the ticket as it takes off.
    const rest = { transform: "translateX(-140%) skewX(-18deg)", opacity: 0 };
    const shine = [
      { ...rest, offset: 0 },
      { ...rest, opacity: 1, offset: step + widen[0] },
      { transform: "translateX(260%) skewX(-18deg)", opacity: 1, offset: step + widen[1] },
      { ...rest, offset: step + widen[1] + 0.001 },
      { ...rest, offset: 1 },
    ];
    return parts.flatMap(({ item, box, panel, acts }, index) => [
      item.animate(ticket, timing(index)),
      box.animate(light, timing(index)),
      box.animate(shine, { ...timing(index), pseudoElement: "::after" }),
      panel.animate(details, timing(index)),
      acts.animate(actions, timing(index)),
    ]);
  }
}
