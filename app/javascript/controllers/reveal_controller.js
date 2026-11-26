import { Controller } from "@hotwired/stimulus";

// A list whose items come in one after the other, the first time it scrolls into view (the landing's four
// "seats" steps). Without JavaScript, or with reduced motion, the items are simply there.
export default class extends Controller {
  connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches || !("IntersectionObserver" in window)) return;

    [...this.element.children].forEach((item, index) => item.style.setProperty("--reveal-i", index));
    this.element.classList.add("reveal-ready");
    this.observer = new IntersectionObserver((entries) => {
      if (!entries.some((entry) => entry.isIntersecting)) return;

      this.element.classList.add("reveal-in");
      this.observer.disconnect();
    }, { threshold: 0.35 });
    this.observer.observe(this.element);
  }

  disconnect() {
    this.observer?.disconnect();
  }
}
