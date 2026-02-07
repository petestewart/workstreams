import { execSync } from "node:child_process";

export function focusChrome(urlPatterns: string[]): boolean {
  if (urlPatterns.length === 0) return false;

  // Convert glob patterns to AppleScript-friendly contains checks
  // "github.com/org/repo/**" → check if URL contains "github.com/org/repo"
  const prefixes = urlPatterns.map((p) => p.replace(/\/?\*\*$/, ""));

  const conditions = prefixes
    .map((prefix) => `theUrl contains "${prefix}"`)
    .join(" or ");

  const script = `
    tell application "System Events"
      if not (exists process "Google Chrome") then return false
    end tell
    tell application "Google Chrome"
      repeat with w in windows
        set tabIndex to 0
        repeat with t in tabs of w
          set tabIndex to tabIndex + 1
          set theUrl to URL of t
          if ${conditions} then
            set active tab index of w to tabIndex
            set index of w to 1
            activate
            return true
          end if
        end repeat
      end repeat
      return false
    end tell
  `;

  try {
    const result = execSync("osascript", {
      input: script,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
    return result === "true";
  } catch {
    return false;
  }
}
