import { Controller } from "@hotwired/stimulus";

// Pod card: tap a player row to pick the winner, then confirm. Confirming submits the hidden per-seat Win form.
export default class extends Controller {
  static targets = ["row", "winForm", "draw", "confirm", "confirmLabel"];
  static values = { template: String };

  connect() {
    this.restore = this.restore.bind(this);
    document.addEventListener("turbo:morph", this.restore);
  }

  disconnect() {
    document.removeEventListener("turbo:morph", this.restore);
  }

  // A live refresh morphs the card back to the server markup: put the pick back, or drop it if the seat can no longer win.
  restore() {
    if (!this.selectedSeat) return;
    const row = this.rowTargets.find((r) => r.dataset.seat === this.selectedSeat);
    const form = this.winFormTargets.find((f) => f.dataset.seat === this.selectedSeat);
    if (row && form) this.mark(row);
    else this.clear();
  }

  // A live pod update replaces the rows (Turbo Stream replace of #pod_X_state, no morph): re-mark the picked seat.
  rowTargetConnected(row) {
    if (this.selectedSeat && row.dataset.seat === this.selectedSeat) this.mark(row);
  }

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
    this.selectedSeat = row.dataset.seat;
    row.dataset.selected = "true";
    row.setAttribute("aria-pressed", "true");
    this.confirmLabelTarget.textContent = this.templateValue.replace("%{name}", row.dataset.name);
    this.drawTarget.hidden = true;
    this.confirmTarget.hidden = false;
  }

  clear() {
    this.selectedSeat = null;
    this.rowTargets.forEach((row) => {
      delete row.dataset.selected;
      row.setAttribute("aria-pressed", "false");
    });
    // A pod completed meanwhile has no footer buttons left to reset.
    if (!this.hasDrawTarget || !this.hasConfirmTarget) return;
    this.drawTarget.hidden = false;
    this.confirmTarget.hidden = true;
  }

  get selectedRow() {
    return this.rowTargets.find((row) => row.dataset.selected === "true");
  }
}
