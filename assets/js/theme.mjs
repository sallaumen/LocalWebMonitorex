export const themeKey = "localwebmonitorex.theme"
const choices = new Set(["auto", "light", "dark"])

export function readTheme(getStorage) {
  try {
    const choice = getStorage().getItem(themeKey)
    return choices.has(choice) ? choice : "auto"
  } catch (_) {
    return "auto"
  }
}

export function saveTheme(getStorage, choice) {
  if (!choices.has(choice)) return false
  try {
    getStorage().setItem(themeKey, choice)
    return true
  } catch (_) {
    return false
  }
}

export function resolveTheme(choice, systemDark) {
  return choice === "dark" || (choice !== "light" && systemDark) ? "dark" : "light"
}
