import { Controller } from "@hotwired/stimulus";

// Landing: a horizontal rail of cards (featured events, featured circuits) with two small arrows that page it
// sideways; the arrows only show when the rail overflows, and each one dims at its end.
export default class extends Controller {
  static targets = ["track", "prev", "next"];

  connect() {
    this.update = this.update.bind(this);
    this.trackTarget.addEventListener("scroll", this.update, { passive: true });
    window.addEventListener("resize", this.update);
    this.update();
  }

  disconnect() {
    this.trackTarget.removeEventListener("scroll", this.update);
    window.removeEventListener("resize", this.update);
  }

  prev() {
    this.page(-1);
  }

  next() {
    this.page(1);
  }

  page(direction) {
    const track = this.trackTarget;
    track.scrollBy({ left: direction * track.clientWidth * 0.9, behavior: "smooth" });
  }

  update() {
    const track = this.trackTarget;
    const overflow = track.scrollWidth - track.clientWidth > 2;
    this.element.toggleAttribute("data-overflow", overflow);
    this.prevTarget.disabled = track.scrollLeft <= 2;
    this.nextTarget.disabled = track.scrollLeft + track.clientWidth >= track.scrollWidth - 2;
  }
}
