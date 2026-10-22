// Date helpers. Dates are stored as "YYYY-MM-DD" strings (local calendar days),
// so there are no time-zone or daylight-saving surprises. Weeks start on Monday.

const pad = (n) => String(n).padStart(2, "0");

export function ymd(y, m, d) {
  return `${y}-${pad(m)}-${pad(d)}`;
}

export function parts(s) {
  const [y, m, d] = s.split("-").map(Number);
  return { y, m, d };
}

/** Today's date on this device. */
export function today(now = new Date()) {
  return ymd(now.getFullYear(), now.getMonth() + 1, now.getDate());
}

function toUTC(s) {
  const { y, m, d } = parts(s);
  return Date.UTC(y, m - 1, d);
}

function fromUTC(ms) {
  const dt = new Date(ms);
  return ymd(dt.getUTCFullYear(), dt.getUTCMonth() + 1, dt.getUTCDate());
}

export function isValid(s) {
  if (typeof s !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const { y, m, d } = parts(s);
  return m >= 1 && m <= 12 && d >= 1 && d <= daysInMonth(y, m);
}

export function addDays(s, n) {
  return fromUTC(toUTC(s) + n * 86400000);
}

export function daysInMonth(y, m) {
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

/** Adds months, keeping the day but clamping to the end of shorter months. */
export function addMonths(s, n) {
  const { y, m, d } = parts(s);
  const total = y * 12 + (m - 1) + n;
  const ny = Math.floor(total / 12);
  const nm = (total % 12) + 1;
  return ymd(ny, nm, Math.min(d, daysInMonth(ny, nm)));
}

/** Whole days from a to b (b − a). */
export function diffDays(a, b) {
  return Math.round((toUTC(b) - toUTC(a)) / 86400000);
}

/** 0 = Monday … 6 = Sunday. */
export function weekday(s) {
  return (new Date(toUTC(s)).getUTCDay() + 6) % 7;
}

export function startOfWeek(s) {
  return addDays(s, -weekday(s));
}

export function startOfMonth(s) {
  const { y, m } = parts(s);
  return ymd(y, m, 1);
}

/** Period containing a date, as { start, end } with `end` exclusive. */
export function periodOf(period, s) {
  if (period === "weekly") {
    const start = startOfWeek(s);
    return { start, end: addDays(start, 7) };
  }
  const start = startOfMonth(s);
  return { start, end: addMonths(start, 1) };
}

export function shiftPeriod(range, period, n) {
  const start = period === "weekly" ? addDays(range.start, 7 * n) : addMonths(range.start, n);
  return periodOf(period, start);
}

export const inRange = (s, range) => s >= range.start && s < range.end;

export const minDate = (a, b) => (a < b ? a : b);
export const maxDate = (a, b) => (a > b ? a : b);

// ---- Repeating schedules ----------------------------------------------------

export const FREQUENCIES = {
  once: { label: "One-off", perYear: 0 },
  weekly: { label: "Weekly", perYear: 52 },
  fortnightly: { label: "Fortnightly", perYear: 26 },
  monthly: { label: "Monthly", perYear: 12 },
  quarterly: { label: "Quarterly", perYear: 4 },
  yearly: { label: "Yearly", perYear: 1 },
};

/** The n-th occurrence counted from the anchor. Months are always added from the
 *  anchor so a bill due on the 31st doesn't drift after a short month. */
export function occurrence(freq, n, anchor) {
  switch (freq) {
    case "once": return n === 0 ? anchor : null;
    case "weekly": return addDays(anchor, 7 * n);
    case "fortnightly": return addDays(anchor, 14 * n);
    case "monthly": return addMonths(anchor, n);
    case "quarterly": return addMonths(anchor, 3 * n);
    case "yearly": return addMonths(anchor, 12 * n);
    default: return null;
  }
}

function firstIndexAfter(freq, date, anchor, inclusive) {
  const days = diffDays(anchor, date);
  const approx = { once: 0, weekly: 7, fortnightly: 14, monthly: 31, quarterly: 92, yearly: 366 }[freq];
  let n = freq === "once" ? 0 : Math.max(0, Math.floor(days / approx) - 1);
  for (let i = 0; i < 1000; i++, n++) {
    const c = occurrence(freq, n, anchor);
    if (c === null) return null;
    if (inclusive ? c >= date : c > date) return n;
  }
  return null;
}

export function nextOccurrence(freq, after, anchor, inclusive = false) {
  const n = firstIndexAfter(freq, after, anchor, inclusive);
  return n === null ? null : occurrence(freq, n, anchor);
}

export function previousOccurrence(freq, onOrBefore, anchor) {
  if (anchor > onOrBefore) return null;
  if (freq === "once") return anchor;
  const n = firstIndexAfter(freq, onOrBefore, anchor, false);
  return n === null || n === 0 ? null : occurrence(freq, n - 1, anchor);
}

// ---- Formatting (Australian) -------------------------------------------------

const fmt = (opts) => new Intl.DateTimeFormat("en-AU", { timeZone: "UTC", ...opts });
const F = {
  dmy: fmt({ day: "2-digit", month: "2-digit", year: "numeric" }),
  wdm: fmt({ weekday: "short", day: "numeric", month: "short" }),
  dm: fmt({ day: "numeric", month: "short" }),
  long: fmt({ day: "numeric", month: "long", year: "numeric" }),
  my: fmt({ month: "long", year: "numeric" }),
  mon: fmt({ month: "short" }),
  wdmy: fmt({ weekday: "short", day: "numeric", month: "short", year: "numeric" }),
};
const asDate = (s) => new Date(toUTC(s));

export const fmtDMY = (s) => F.dmy.format(asDate(s));           // 22/10/2026
export const fmtWeekday = (s) => F.wdm.format(asDate(s)).replace(",", ""); // Thu 22 Oct
export const fmtDayMonth = (s) => F.dm.format(asDate(s));       // 22 Oct
export const fmtLong = (s) => F.long.format(asDate(s));         // 22 October 2026
export const fmtMonthYear = (s) => F.my.format(asDate(s));      // October 2026
export const fmtMonth = (s) => F.mon.format(asDate(s));         // Oct

/** "Today", "Yesterday" or "Thu 22 Oct". */
export function fmtDayHeader(s, now) {
  const diff = diffDays(s, now);
  if (diff === 0) return "Today";
  if (diff === 1) return "Yesterday";
  if (parts(s).y === parts(now).y) return fmtWeekday(s);
  return F.wdmy.format(asDate(s)).replace(",", "");
}

/** "Due today", "Due tomorrow", "In 3 days", "2 days overdue". */
export function fmtDue(s, now) {
  const days = diffDays(now, s);
  if (days < -1) return `${-days} days overdue`;
  if (days === -1) return "1 day overdue";
  if (days === 0) return "Due today";
  if (days === 1) return "Due tomorrow";
  if (days < 7) return `In ${days} days · ${fmtWeekday(s)}`;
  return fmtWeekday(s);
}

/** Parses dd/mm/yyyy, d/m/yy or yyyy-mm-dd into "YYYY-MM-DD". */
export function parseAUDate(text) {
  const t = String(text || "").trim();
  let m = t.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);
  if (m) {
    const s = ymd(+m[1], +m[2], +m[3]);
    return isValid(s) ? s : null;
  }
  m = t.match(/^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2}|\d{4})$/);
  if (m) {
    let y = +m[3];
    if (y < 100) y += 2000;
    const s = ymd(y, +m[2], +m[1]);
    return isValid(s) ? s : null;
  }
  return null;
}
