import { Controller } from "@hotwired/stimulus";

// Roster: the "+" on a row shows or hides the stats row that follows it.
export default class extends Controller {
  toggle(event) {
    const button = event.currentTarget;
    const row = document.getElementById(button.getAttribute("aria-controls"));
    if (!row) return;

    const open = row.hidden;
    row.hidden = !open;
    button.setAttribute("aria-expanded", String(open));
    button.querySelector("[data-sign]").textContent = open ? "−" : "+";
  }
}
