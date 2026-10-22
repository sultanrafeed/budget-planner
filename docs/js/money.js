// Money is stored as whole cents (integers) so totals are always exact.

const AUD = new Intl.NumberFormat("en-AU", { style: "currency", currency: "AUD" });
const AUD0 = new Intl.NumberFormat("en-AU", { style: "currency", currency: "AUD", maximumFractionDigits: 0, minimumFractionDigits: 0 });

/** "$1,234.56" (negative: "-$1,234.56") */
export const money = (cents) => AUD.format(cents / 100);

/** "$1,235" */
export const money0 = (cents) => AUD0.format(Math.round(cents / 100));

/** "+$12.00" / "-$12.00" */
export const signedMoney = (cents) => (cents < 0 ? "-" + money(-cents) : "+" + money(cents));

export const MAX_CENTS = 1_000_000_000; // $10 million

/** Parses "12.5", "$1,200", "(54.20)" or "-54.20" into cents, or null. */
export function parseMoney(text) {
  let t = String(text ?? "").replace(/AUD|\$|,|\s/g, "");
  let negative = false;
  if (/^\(.*\)$/.test(t)) {
    negative = true;
    t = t.slice(1, -1);
  }
  if (t.startsWith("-")) {
    negative = !negative;
    t = t.slice(1);
  } else if (t.startsWith("+")) {
    t = t.slice(1);
  }
  if (!/^(\d+(\.\d*)?|\.\d+)$/.test(t)) return null;
  const [whole, frac = ""] = t.split(".");
  const cents = Number(whole || "0") * 100 + Number((frac + "00").slice(0, 2)) + (Number(frac[2] || 0) >= 5 ? 1 : 0);
  return negative ? -cents : cents;
}

/** A friendly problem with an amount the user typed, or null if it's fine. */
export function amountProblem(text, { allowZero = false } = {}) {
  if (!String(text ?? "").trim()) return "Enter an amount.";
  const c = parseMoney(text);
  if (c === null) return "That doesn't look like an amount.";
  if (c < 0) return "Enter the amount without a minus sign.";
  if (c === 0 && !allowZero) return "The amount must be more than $0.";
  if (c > MAX_CENTS) return "That amount is too large.";
  return null;
}

/** Cents → text for an input box, e.g. 1250 → "12.50", 30000 → "300". */
export function centsToInput(cents) {
  if (!cents) return "";
  return cents % 100 === 0 ? String(cents / 100) : (cents / 100).toFixed(2);
}

export const sum = (items, pick = (x) => x) => items.reduce((total, x) => total + pick(x), 0);
