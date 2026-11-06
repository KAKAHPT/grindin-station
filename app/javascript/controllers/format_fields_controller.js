import { Controller } from "@hotwired/stimulus";

// Tournament form: one Format select (Commander / cEDH = pods, any other game format = 1v1). The match length shows only for 1v1, the pairing
// mode only for multiplayer; switching the format resets the points to that side's defaults (unless the organiser already typed some) and
// swaps the top cut sizes it allows.
export default class extends Controller {
  static targets = ["format", "matchGames", "pairing", "standingsExtras", "points", "topCut"];
  static values = { points: Object, cutOptions: Object };

  // Points that came back from the server off the format's defaults (a failed create) count as typed.
  connect() {
    const defaults = this.pointsValue[this.format] || {};
    this.pointsTargets.forEach((input) => {
      const value = defaults[input.dataset.attribute];
      if (value !== undefined && input.value !== String(value)) input.dataset.touched = "true";
    });
  }

  touch(event) {
    event.currentTarget.dataset.touched = "true";
  }

  get format() {
    return this.formatTarget.value === "commander" ? "multiplayer" : "one_v_one";
  }

  change() {
    const format = this.format;
    this.matchGamesTarget.hidden = format !== "one_v_one";
    this.pairingTarget.hidden = format === "one_v_one";
    if (this.hasStandingsExtrasTarget) this.standingsExtrasTarget.hidden = format === "one_v_one";

    if (!this.pointsTargets.some((input) => input.dataset.touched)) {
      const defaults = this.pointsValue[format] || {};
      this.pointsTargets.forEach((input) => {
        if (input.dataset.attribute in defaults) input.value = defaults[input.dataset.attribute];
      });
    }

    if (this.hasTopCutTarget) this.swapCutOptions(this.cutOptionsValue[format] || []);
  }

  // Keeps the blank "Suggested" option and the current pick when the new format allows it.
  swapCutOptions(options) {
    const select = this.topCutTarget;
    const current = select.value;
    [...select.options].filter((option) => option.value !== "").forEach((option) => option.remove());
    options.forEach(([label, value]) => select.add(new Option(label, value)));
    select.value = options.some(([, value]) => String(value) === current) ? current : "";
  }
}
