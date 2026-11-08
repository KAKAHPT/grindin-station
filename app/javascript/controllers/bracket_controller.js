import { Controller } from "@hotwired/stimulus";

// Public top-cut bracket: draws the wires between the stages' table cards (an SVG overlay sized to the layout)
// and, under 640 px, shows one stage at a time through the tabs. Redrawn on resize, after a live morph refresh
// and when the pairings search hides cards.
export default class extends Controller {
  static targets = ["wires", "stage", "tab"];
  static values = { open: Number };

  connect() {
    this.redraw = this.redraw.bind(this);
    this.show(this.openValue);
    addEventListener("resize", this.redraw);
    document.addEventListener("turbo:morph", this.redraw);
    document.addEventListener("input", this.redraw);
    if (document.fonts?.ready) document.fonts.ready.then(this.redraw);
    this.redraw();
  }

  disconnect() {
    removeEventListener("resize", this.redraw);
    document.removeEventListener("turbo:morph", this.redraw);
    document.removeEventListener("input", this.redraw);
  }

  open({ params: { number } }) {
    this.show(number);
  }

  show(number) {
    this.stageTargets.forEach((stage) => { stage.dataset.open = Number(stage.dataset.bracketStage) === number; });
    this.tabTargets.forEach((tab) => {
      const on = Number(tab.dataset.bracketNumberParam) === number;
      tab.classList.toggle("seg-on", on);
      if (on) tab.setAttribute("aria-current", "true"); else tab.removeAttribute("aria-current");
    });
  }

  redraw() {
    if (!this.hasWiresTarget) return;
    const svg = this.wiresTarget;
    if (getComputedStyle(svg).display === "none") return;
    const origin = this.element.getBoundingClientRect();
    const box = (el) => {
      const r = el.getBoundingClientRect();
      return { x: r.left - origin.left + r.width / 2, top: r.top - origin.top, bottom: r.bottom - origin.top };
    };
    const groups = this.stageTargets.map((stage) =>
      [...stage.querySelectorAll("[data-bracket-card]")].filter((card) => !card.hidden)
    );
    let d = "";
    for (let i = 0; i < groups.length - 1; i++) {
      const from = groups[i].map(box);
      const to = groups[i + 1].map(box);
      if (!from.length || !to.length) continue;
      const y = Math.max(...from.map((b) => b.bottom)) + 28;
      // A 1v1 bracket wires each pair of tables to its own next table; a reseeded cut shares one bus.
      const pairs = from.length === to.length * 2 && !groups[i].some((card) => card.hasAttribute("data-byes"));
      const sets = pairs ? to.map((t, j) => [[from[2 * j], from[2 * j + 1]], [t]]) : [[from, to]];
      for (const [f, t] of sets) {
        const xs = [...f, ...t].map((b) => b.x);
        d += `M${Math.min(...xs)} ${y}H${Math.max(...xs)}`;
        f.forEach((b) => { d += `M${b.x} ${b.bottom}V${y}`; });
        t.forEach((b) => { d += `M${b.x} ${y}V${b.top}`; });
      }
    }
    svg.querySelector("path").setAttribute("d", d);
  }
}
