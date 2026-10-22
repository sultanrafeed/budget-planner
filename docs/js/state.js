// Screen state that isn't saved with your data (current tab, filters…).
// A few conveniences are remembered on this device.

const saved = (() => {
  try {
    return JSON.parse(localStorage.getItem("budgetPlanner.ui") || "{}");
  } catch {
    return {};
  }
})();

export const ui = {
  tab: "home",
  planPage: "budgets",
  insightsPage: "spending",
  search: "",
  kindFilter: "all",
  categoryFilter: "",
  monthFilter: "",
  spendPeriod: "monthly",
  spendOffset: 0,
  reportPeriod: "monthly",
  whatIf: null,
  hideInstallHint: false,
  ...saved,
};

export function remember() {
  try {
    const { tab, planPage, insightsPage, hideInstallHint } = ui;
    localStorage.setItem("budgetPlanner.ui", JSON.stringify({ tab, planPage, insightsPage, hideInstallHint }));
  } catch {}
}
