import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import type { ItermMatch, ChromeMatch, GenericMatch, WindowMatch } from "./state";

const IT2API = "/Applications/iTerm.app/Contents/Resources/utilities/it2api";

export function activateItermMatch(match: ItermMatch): boolean {
  try {
    if (existsSync(IT2API)) {
      execFileSync(IT2API, ["activate", "tab", match.tab_id], {
        stdio: ["pipe", "pipe", "pipe"],
      });
      execFileSync(IT2API, ["activate", "window", match.window_id], {
        stdio: ["pipe", "pipe", "pipe"],
      });
    }
    execFileSync("/usr/bin/osascript", {
      input: 'tell application "iTerm" to activate',
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    });
    return true;
  } catch {
    return false;
  }
}

export function activateChromeMatch(match: ChromeMatch): boolean {
  const script = `tell application "Google Chrome"
  set active tab index of window ${match.window_index} to ${match.tab_index}
  set index of window ${match.window_index} to 1
  activate
end tell`;

  try {
    execFileSync("/usr/bin/osascript", {
      input: script,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    });
    return true;
  } catch {
    return false;
  }
}

export function activateGenericMatch(match: GenericMatch): boolean {
  const script = `tell application "System Events"
  set frontmost of process "${match.process_name}" to true
end tell`;

  try {
    execFileSync("/usr/bin/osascript", {
      input: script,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    });
    return true;
  } catch {
    return false;
  }
}

export function activateMatch(match: WindowMatch): boolean {
  if ("session_id" in match) {
    return activateItermMatch(match);
  }
  if ("url" in match) {
    return activateChromeMatch(match);
  }
  return activateGenericMatch(match);
}
