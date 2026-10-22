// Categories based on common Australian living costs.

export const CATEGORIES = {
  // Spending
  rent: { kind: "expense", name: "Rent", icon: "🏠", color: "#5856D6", hint: "Rent, board, bond, strata" },
  groceries: { kind: "expense", name: "Groceries", icon: "🛒", color: "#34C759", hint: "Woolworths, Coles, Aldi, IGA" },
  transport: { kind: "expense", name: "Transport", icon: "🚆", color: "#007AFF", hint: "Opal, Myki, go card, fuel, rego, tolls" },
  utilities: { kind: "expense", name: "Bills & Utilities", icon: "💡", color: "#FFB800", hint: "Electricity, gas, water" },
  phoneInternet: { kind: "expense", name: "Phone & Internet", icon: "📱", color: "#32ADE6", hint: "Mobile plan, NBN" },
  insurance: { kind: "expense", name: "Insurance", icon: "🛡️", color: "#73859E", hint: "Car, contents, health cover" },
  health: { kind: "expense", name: "Health", icon: "💊", color: "#FF3B30", hint: "GP gap, pharmacy, dentist" },
  education: { kind: "expense", name: "Education", icon: "🎓", color: "#AF52DE", hint: "Uni fees, textbooks, courses" },
  eatingOut: { kind: "expense", name: "Eating Out", icon: "🍜", color: "#FF9500", hint: "Takeaway, cafés, coffee" },
  shopping: { kind: "expense", name: "Shopping", icon: "🛍️", color: "#FF2D55", hint: "Clothes, Kmart, online" },
  entertainment: { kind: "expense", name: "Entertainment", icon: "🎟️", color: "#00C7BE", hint: "Movies, concerts, sport" },
  subscriptions: { kind: "expense", name: "Subscriptions", icon: "🔁", color: "#30B0C7", hint: "Netflix, Spotify, gym" },
  personalCare: { kind: "expense", name: "Personal Care", icon: "💇", color: "#A2845E", hint: "Haircut, toiletries" },
  gifts: { kind: "expense", name: "Gifts & Donations", icon: "🎁", color: "#DB5C8C", hint: "Presents, charity" },
  travel: { kind: "expense", name: "Travel", icon: "✈️", color: "#3399DB", hint: "Flights, accommodation" },
  otherExpense: { kind: "expense", name: "Other", icon: "📦", color: "#8E8E93", hint: "Anything else" },
  // Income
  salary: { kind: "income", name: "Salary", icon: "💼", color: "#34C759", hint: "Full-time pay" },
  partTime: { kind: "income", name: "Part-time Work", icon: "⏰", color: "#30D158", hint: "Casual or part-time shifts" },
  centrelink: { kind: "income", name: "Centrelink", icon: "🏛️", color: "#007AFF", hint: "Youth Allowance, payments" },
  freelance: { kind: "income", name: "Side Work", icon: "💻", color: "#30B0C7", hint: "Tutoring, gigs, selling items" },
  taxRefund: { kind: "income", name: "Tax Refund", icon: "🧾", color: "#5856D6", hint: "ATO refund" },
  giftIncome: { kind: "income", name: "Gift", icon: "💝", color: "#FF2D55", hint: "Money from family or friends" },
  otherIncome: { kind: "income", name: "Other Income", icon: "➕", color: "#8E8E93", hint: "Interest, refunds, other" },
};

export const cat = (id) => CATEGORIES[id] || CATEGORIES.otherExpense;

export const categoriesFor = (kind) => Object.keys(CATEGORIES).filter((id) => CATEGORIES[id].kind === kind);

/** Finds a category from free text (CSV import). */
export function matchCategory(text, kind) {
  const needle = String(text || "").trim().toLowerCase();
  const ids = categoriesFor(kind);
  const exact = ids.find((id) => id.toLowerCase() === needle || CATEGORIES[id].name.toLowerCase() === needle);
  if (exact) return exact;
  const loose = needle && ids.find((id) => CATEGORIES[id].name.toLowerCase().includes(needle));
  return loose || (kind === "income" ? "otherIncome" : "otherExpense");
}

export const GOAL_ICONS = ["⭐️", "🛟", "✈️", "🚗", "💻", "🏡", "🎓", "🎁", "❤️", "📱", "🚲", "🐶", "🎵", "📷", "✨"];
