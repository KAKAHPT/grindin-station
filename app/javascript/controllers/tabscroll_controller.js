import { Controller } from "@hotwired/stimulus";

// A tab bar wider than the screen (phones): the open tab is brought into view, and the bar fades at each end
// that still has tabs beyond it, so it reads as something to swipe.
export default class extends Controller {
  connect() {
    this.update = this.update.bind(this);
    this.element.addEventListener("scroll", this.update, { passive: true });
    window.addEventListener("resize", this.update);
    const open = this.element.querySelector("[aria-current]");
    if (open) this.element.scrollLeft = open.offsetLeft - (this.element.clientWidth - open.offsetWidth) / 2;
    this.update();
  }

  disconnect() {
    this.element.removeEventListener("scroll", this.update);
    window.removeEventListener("resize", this.update);
  }

  update() {
    const { scrollLeft, scrollWidth, clientWidth } = this.element;
    this.element.toggleAttribute("data-more-before", scrollLeft > 2);
    this.element.toggleAttribute("data-more-after", scrollLeft + clientWidth < scrollWidth - 2);
  }
}
