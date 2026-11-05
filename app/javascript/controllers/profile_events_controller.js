import { Controller } from "@hotwired/stimulus";

// Public profile: filters (search, year, season), sorts and pages the events table, opens an event's detail row
// with the "+" and recomputes the band (stats, achievements, most played commanders) from the matching rows, with
// the same figures as Profiles::Summary. Without JavaScript the server-rendered table and totals stay as they are.
// The toolbar and the "+" buttons sit in partials, so their clicks and changes reach this element and are picked
// out by what was clicked. Rows past PAGE stay hidden until "Show all"; filtering closes details and resets it.
const PAGE = 6;
const OPEN = ["bg-ink", "text-ground", "border-ink"];
const CLOSED = ["border-line-strong", "text-muted"];
const DEFAULT_DIR = { date: -1, name: 1, position: 1 };

export default class extends Controller {
  static targets = ["search", "table", "more", "noMatch", "header"];

  connect() {
    if (!this.hasTableTarget) return;
    this.rows = [...this.tableTarget.querySelectorAll("tr[data-event]")];
    this.details = new Map(this.rows.map((row) => [row, row.nextElementSibling]));
    this.summary = this.element.querySelector("[data-profile-summary]");
    this.count = this.element.querySelector("[data-count]");
    this.yearFilter = "all";
    this.seasonFilter = "all";
    this.expanded = false;
    this.sortKey = "date";
    this.sortDir = -1;
    this.render();
  }

  search(event) {
    if (event.target !== this.searchTarget) return;
    this.filtered();
  }

  year(event) {
    const button = event.target.closest("[data-year]");
    if (!button) return;
    this.yearFilter = button.dataset.year;
    this.element.querySelectorAll("[data-year]").forEach((b) => {
      const on = b === button;
      b.classList.toggle("seg-on", on);
      b.setAttribute("aria-pressed", String(on));
    });
    this.filtered();
  }

  season(event) {
    if (!event.target.matches("[data-season]")) return;
    this.seasonFilter = event.target.value;
    this.filtered();
  }

  sort(event) {
    if (event.type === "keydown") {
      if (event.key !== "Enter" && event.key !== " ") return;
      event.preventDefault();
    }
    const key = event.currentTarget.dataset.sort;
    this.sortDir = key === this.sortKey ? -this.sortDir : DEFAULT_DIR[key];
    this.sortKey = key;
    this.headerTargets.forEach((th) => {
      const on = th.dataset.sort === key;
      th.classList.toggle("text-ink", on);
      if (on) th.setAttribute("aria-sort", this.sortDir > 0 ? "ascending" : "descending");
      else th.removeAttribute("aria-sort");
    });
    const body = this.tableTarget.tBodies[0];
    this.rows.sort((a, b) => this.compare(a, b));
    this.rows.forEach((row) => {
      body.insertBefore(row, this.noMatchTarget);
      body.insertBefore(this.details.get(row), this.noMatchTarget);
    });
    this.render();
  }

  toggle(event) {
    const button = event.target.closest("button[aria-controls]");
    if (!button || !button.closest("tr[data-event]")) return;
    this.setOpen(button.closest("tr[data-event]"), button.getAttribute("aria-expanded") !== "true");
  }

  more() {
    this.expanded = !this.expanded;
    this.render();
  }

  // private

  filtered() {
    this.expanded = false;
    this.rows.forEach((row) => this.setOpen(row, false));
    this.render();
  }

  compare(a, b) {
    const x = a.dataset[this.sortKey];
    const y = b.dataset[this.sortKey];
    if (this.sortKey === "position") {
      if (x === "" || y === "") return (x === "") - (y === "");
      return (Number(x) - Number(y)) * this.sortDir;
    }
    if (this.sortKey === "name") return x.localeCompare(y) * this.sortDir;
    return (x < y ? -1 : x > y ? 1 : 0) * this.sortDir;
  }

  matches(row) {
    const q = this.hasSearchTarget ? this.searchTarget.value.trim().toLowerCase() : "";
    const d = row.dataset;
    const text = [d.name, d.organizer, d.commander].join(" ").toLowerCase();
    return (q === "" || text.includes(q)) && (this.yearFilter === "all" || d.year === this.yearFilter) &&
      (this.seasonFilter === "all" || d.season === this.seasonFilter);
  }

  setOpen(row, open) {
    const button = row.querySelector("button[aria-controls]");
    this.details.get(row).hidden = !open;
    button.setAttribute("aria-expanded", String(open));
    button.classList.remove(...(open ? CLOSED : OPEN));
    button.classList.add(...(open ? OPEN : CLOSED));
    button.querySelector("[data-sign]").textContent = open ? "–" : "+";
  }

  render() {
    const matched = this.rows.filter((row) => this.matches(row));
    const shown = this.expanded ? matched : matched.slice(0, PAGE);
    this.rows.forEach((row) => {
      const index = shown.indexOf(row);
      row.hidden = index < 0;
      if (row.hidden) this.setOpen(row, false);
      row.toggleAttribute("data-odd", index % 2 === 0);
      row.toggleAttribute("data-last", index >= 0 && index === shown.length - 1);
    });
    this.noMatchTarget.hidden = matched.length > 0;
    this.count.textContent = this.count.dataset.template
      .replace("%{shown}", matched.length).replace("%{total}", this.rows.length);
    if (this.hasMoreTarget) {
      const more = this.moreTarget;
      more.parentElement.hidden = matched.length <= PAGE;
      more.textContent = this.expanded ? more.dataset.showLess : more.dataset.showAll.replace("%{count}", matched.length);
    }
    this.renderSummary(matched);
  }

  renderSummary(rows) {
    const sum = (key) => rows.reduce((total, row) => total + Number(row.dataset[key]), 0);
    const positions = rows.map((row) => Number(row.dataset.position || 0)).filter((p) => p > 0);
    const cuts = rows.filter((row) => row.dataset.cut === "1").length;
    const set = (selector, value) => { this.summary.querySelector(selector).textContent = value; };
    set("[data-stat=events]", rows.length);
    set("[data-stat=top_cuts]", cuts);
    set("[data-stat=win_rate]", percent(sum("wins"), sum("wins") + sum("losses") + sum("draws")));
    set("[data-stat=conversion]", percent(cuts, rows.length));
    set("[data-ach=wins]", positions.filter((p) => p === 1).length);
    set("[data-ach=top4]", positions.filter((p) => p <= 4).length);
    set("[data-ach=cuts]", cuts);
    this.renderCommanders(rows);
  }

  renderCommanders(rows) {
    const tally = new Map();
    rows.forEach(({ dataset: { commander } }) => {
      if (commander) tally.set(commander, (tally.get(commander) || 0) + 1);
    });
    const top = [...tally].sort(([a, x], [b, y]) => y - x || (a < b ? -1 : a > b ? 1 : 0)).slice(0, 4);
    const items = top.map(([name, count]) => {
      const share = Math.round((count * 100) / rows.length);
      const li = element("li", "grid grid-cols-[1fr_auto] items-center gap-x-2.5 text-[12.5px]");
      li.append(element("b", "font-display text-xs font-semibold text-ink truncate", name),
        element("span", "text-[11.5px] text-muted tabular", `${count} · ${share}%`));
      const bar = element("span", "col-span-full h-[3px] rounded-sm bg-line");
      const fill = element("i", "block h-full rounded-sm bg-muted");
      fill.style.width = `${share}%`;
      bar.setAttribute("aria-hidden", "true");
      bar.append(fill);
      li.append(bar);
      return li;
    });
    if (items.length === 0) items.push(element("li", "text-[11.5px] text-muted", "–"));
    this.summary.querySelector("[data-commanders]").replaceChildren(...items);
  }
}

function percent(part, whole) {
  return whole === 0 ? "–" : `${Math.round((part * 100) / whole)}%`;
}

function element(tag, className, text) {
  const node = document.createElement(tag);
  node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}
