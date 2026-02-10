import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import type { ItermMatch } from "../types.js";

const IT2API = "/Applications/iTerm.app/Contents/Resources/utilities/it2api";

interface HierarchyEntry {
  windowId: string;
  tabId: string;
  sessionName: string;
}

function parseHierarchy(output: string): Map<string, HierarchyEntry> {
  // Map session ID → { windowId, tabId, sessionName }
  const map = new Map<string, HierarchyEntry>();
  let currentWindow = "";
  let currentTab = "";

  for (const line of output.split("\n")) {
    const windowMatch = line.match(/^Window id=(\S+)/);
    if (windowMatch) {
      currentWindow = windowMatch[1];
      continue;
    }
    const tabMatch = line.match(/^\s+Tab id=(\S+)/);
    if (tabMatch) {
      currentTab = tabMatch[1];
      continue;
    }
    const sessionMatch = line.match(/Session "([^"]*)" id=(\S+)/);
    if (sessionMatch) {
      map.set(sessionMatch[2], {
        windowId: currentWindow,
        tabId: currentTab,
        sessionName: sessionMatch[1],
      });
      continue;
    }
    // Fallback: session line without quoted name
    const sessionFallback = line.match(/Session .+ id=(\S+)/);
    if (sessionFallback) {
      map.set(sessionFallback[1], {
        windowId: currentWindow,
        tabId: currentTab,
        sessionName: "",
      });
    }
  }
  return map;
}

function isItermRunning(): boolean {
  try {
    const check = execSync("osascript", {
      input: `tell application "System Events" to return exists process "iTerm2"`,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
    return check === "true";
  } catch {
    return false;
  }
}

export function detectIterm(projectPath: string): ItermMatch[] {
  if (!isItermRunning()) return [];

  // Find ALL sessions whose shell cwd starts with projectPath
  const script = `
tell application "iTerm"
  set matchedIds to {}
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        try
          set sessionTTY to tty of s
          set ttyName to do shell script "basename " & quoted form of sessionTTY
          set shellPID to do shell script "ps -t " & ttyName & " -o pid=,comm= | grep -E 'zsh|bash|fish' | head -1 | awk '{print $1}'"
          if shellPID is not "" then
            set sessionPath to do shell script "lsof -a -p " & shellPID & " -d cwd -Fn 2>/dev/null | awk '/^n/{print substr($0,2)}'"
            if sessionPath starts with "${projectPath}" then
              set end of matchedIds to id of s
            end if
          end if
        end try
      end repeat
    end repeat
  end repeat
  set AppleScript's text item delimiters to "||"
  return matchedIds as text
end tell
`;

  try {
    const result = execSync("osascript", {
      input: script,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();

    if (!result) return [];

    const sessionIds = result.split("||");

    // Get hierarchy to map session IDs to window/tab IDs and names
    const hierarchy = execSync(`${IT2API} show-hierarchy`, {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    });
    const map = parseHierarchy(hierarchy);

    const matches: ItermMatch[] = [];
    for (const sessionId of sessionIds) {
      const info = map.get(sessionId);
      if (info) {
        matches.push({
          app: "iTerm",
          window_id: info.windowId,
          tab_id: info.tabId,
          session_id: sessionId,
          title: info.sessionName || sessionId,
        });
      }
    }
    return matches;
  } catch {
    return [];
  }
}

export function activateIterm(match: ItermMatch): boolean {
  try {
    if (existsSync(IT2API)) {
      execSync(`${IT2API} activate tab ${match.tab_id}`, {
        stdio: ["pipe", "pipe", "pipe"],
      });
      execSync(`${IT2API} activate window ${match.window_id}`, {
        stdio: ["pipe", "pipe", "pipe"],
      });
    }
    execSync("osascript", {
      input: `tell application "iTerm" to activate`,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    });
    return true;
  } catch {
    return false;
  }
}

export function focusIterm(projectPath: string): boolean {
  const matches = detectIterm(projectPath);
  if (matches.length === 0) return false;

  // Activate the first match (preserves original behavior)
  return activateIterm(matches[0]);
}
