import { execSync } from "node:child_process";
import type { ChromeMatch } from "../types.js";

function buildConditions(urlPatterns: string[]): string {
  const prefixes = urlPatterns.map((p) => p.replace(/\/?\*\*$/, ""));
  return prefixes.map((prefix) => `theUrl contains "${prefix}"`).join(" or ");
}

export function detectChrome(urlPatterns: string[]): ChromeMatch[] {
  if (urlPatterns.length === 0) return [];

  const conditions = buildConditions(urlPatterns);

  const script = `
    tell application "System Events"
      if not (exists process "Google Chrome") then return ""
    end tell
    tell application "Google Chrome"
      set matchLines to {}
      set winIdx to 0
      repeat with w in windows
        set winIdx to winIdx + 1
        set tabIdx to 0
        repeat with t in tabs of w
          set tabIdx to tabIdx + 1
          set theUrl to URL of t
          if ${conditions} then
            set tabTitle to title of t
            set end of matchLines to (winIdx as text) & "||" & (tabIdx as text) & "||" & tabTitle & "||" & theUrl
          end if
        end repeat
      end repeat
      set AppleScript's text item delimiters to "\\n"
      return matchLines as text
    end tell
  `;

  try {
    const result = execSync("osascript", {
      input: script,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();

    if (!result) return [];

    return result.split("\n").map((line) => {
      const [winIdx, tabIdx, title, ...urlParts] = line.split("||");
      return {
        app: "Chrome" as const,
        window_index: parseInt(winIdx, 10),
        tab_index: parseInt(tabIdx, 10),
        title,
        url: urlParts.join("||"), // rejoin in case URL contained ||
      };
    });
  } catch {
    return [];
  }
}

export function activateChrome(match: ChromeMatch): boolean {
  const script = `
    tell application "Google Chrome"
      set active tab index of window ${match.window_index} to ${match.tab_index}
      set index of window ${match.window_index} to 1
      activate
    end tell
  `;

  try {
    execSync("osascript", {
      input: script,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    });
    return true;
  } catch {
    return false;
  }
}

export function focusChrome(urlPatterns: string[]): boolean {
  const matches = detectChrome(urlPatterns);
  if (matches.length === 0) return false;

  // Activate the first match (preserves original behavior)
  return activateChrome(matches[0]);
}
