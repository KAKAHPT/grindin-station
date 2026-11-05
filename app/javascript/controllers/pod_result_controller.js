import { Controller } from "@hotwired/stimulus";

// Pod card: tap a player row (or Draw) to pick the result, then Confirm. Confirming submits the hidden per-seat Win
// form, or the hidden Draw form when Draw was picked. 1v1 cards confirm with a score button (its games param fills
// the form's result[games]) and their Draw opens the draw scores.
export default class extends Controller {
  static targets = ["row", "winForm", "draw", "confirm", "confirmLabel", "drawScores", "drawForm"];
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
    if (this.drawOpen) {
      if (this.hasDrawScoresTarget) this.showDrawScores();
      else this.clear();
      return;
    }
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

  confirm(event) {
    if (this.drawPicked) {
      this.drawFormTarget.requestSubmit();
      return;
    }
    const row = this.selectedRow;
    if (!row) return;
    const form = this.winFormTargets.find((f) => f.dataset.seat === row.dataset.seat);
    if (!form) return;
    const games = event?.params?.games;
    if (games) form.querySelector("input[name='result[games]']").value = games;
    form.requestSubmit();
  }

  cancel() {
    this.clear();
  }

  openDraw() {
    this.clear();
    this.drawOpen = true;
    this.showDrawScores();
  }

  // Multiplayer: Draw is picked like a winner and waits for Confirm.
  pickDraw() {
    this.clear();
    this.drawPicked = true;
    this.drawTarget.hidden = true;
    this.confirmTarget.hidden = false;
  }

  showDrawScores() {
    this.drawTarget.hidden = true;
    this.drawScoresTarget.hidden = false;
  }

  mark(row) {
    this.selectedSeat = row.dataset.seat;
    row.dataset.selected = "true";
    row.setAttribute("aria-pressed", "true");
    if (this.hasConfirmLabelTarget) this.confirmLabelTarget.textContent = this.templateValue.replace("%{name}", row.dataset.name);
    this.drawTarget.hidden = true;
    this.confirmTarget.hidden = false;
  }

  clear() {
    this.selectedSeat = null;
    this.drawOpen = false;
    this.drawPicked = false;
    this.rowTargets.forEach((row) => {
      delete row.dataset.selected;
      row.setAttribute("aria-pressed", "false");
    });
    // A pod completed meanwhile has no footer buttons left to reset.
    if (!this.hasDrawTarget || !this.hasConfirmTarget) return;
    this.drawTarget.hidden = false;
    this.confirmTarget.hidden = true;
    if (this.hasDrawScoresTarget) this.drawScoresTarget.hidden = true;
  }

  get selectedRow() {
    return this.rowTargets.find((row) => row.dataset.selected === "true");
  }
}
