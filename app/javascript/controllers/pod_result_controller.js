import { Controller } from "@hotwired/stimulus";

// Pod card: tap a player row to pick the winner, then confirm. Confirming submits the hidden per-seat Win form.
export default class extends Controller {
  static targets = ["row", "winForm", "draw", "confirm", "confirmLabel"];
  static values = { template: String };

  select(event) {
    // Swap / penalty links inside the row keep their own behaviour and do not pick the row.
    if (event.target.closest("a, button, form")) return;
    if (event.type === "keydown") event.preventDefault();
    const row = event.currentTarget;
    const current = this.selectedRow;
    this.clear();
    if (row !== current) this.mark(row);
  }

  confirm() {
    const row = this.selectedRow;
    if (!row) return;
    const form = this.winFormTargets.find((f) => f.dataset.seat === row.dataset.seat);
    if (form) form.requestSubmit();
  }

  cancel() {
    this.clear();
  }

  mark(row) {
    row.dataset.selected = "true";
    row.setAttribute("aria-pressed", "true");
    this.confirmLabelTarget.textContent = this.templateValue.replace("%{name}", row.dataset.name);
    this.drawTarget.hidden = true;
    this.confirmTarget.hidden = false;
  }

  clear() {
    this.rowTargets.forEach((row) => {
      delete row.dataset.selected;
      row.setAttribute("aria-pressed", "false");
    });
    this.drawTarget.hidden = false;
    this.confirmTarget.hidden = true;
  }

  get selectedRow() {
    return this.rowTargets.find((row) => row.dataset.selected === "true");
  }
}
