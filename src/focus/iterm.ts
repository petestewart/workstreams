import { execSync } from "node:child_process";
import { existsSync } from "node:fs";

const IT2API = "/Applications/iTerm.app/Contents/Resources/utilities/it2api";

interface TabMatch {
  windowId: string;
  tabId: string;
  sessionId: string;
}

function parseHierarchy(output: string): Map<string, { windowId: string; tabId: string }> {
  // Map session ID → { windowId, tabId }
  const map = new Map<string, { windowId: string; tabId: string }>();
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
    const sessionMatch = line.match(/Session .+ id=(\S+)/);
    if (sessionMatch) {
      map.set(sessionMatch[1], { windowId: currentWindow, tabId: currentTab });
    }
  }
  return map;
}

function findMatchingSession(projectPath: string): TabMatch | null {
  // Use AppleScript to find the session whose tty's shell cwd matches projectPath
  const script = `
tell application "iTerm"
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
              return id of s
            end if
          end if
        end try
      end repeat
    end repeat
  end repeat
  return ""
end tell
`;

  try {
    const sessionId = execSync("osascript", {
      input: script,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
    if (!sessionId) return null;

    // Get hierarchy to find the tab ID for this session
    const hierarchy = execSync(`${IT2API} show-hierarchy`, {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    });
    const map = parseHierarchy(hierarchy);
    const info = map.get(sessionId);
    if (!info) return null;

    return { ...info, sessionId };
  } catch {
    return null;
  }
}

export function focusIterm(projectPath: string): boolean {
  // Check iTerm is running
  try {
    const check = execSync("osascript", {
      input: `tell application "System Events" to return exists process "iTerm2"`,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
    if (check !== "true") return false;
  } catch {
    return false;
  }

  const match = findMatchingSession(projectPath);
  if (!match) return false;

  // Use it2api to activate the tab (works without System Events permissions)
  try {
    if (existsSync(IT2API)) {
      execSync(`${IT2API} activate tab ${match.tabId}`, {
        stdio: ["pipe", "pipe", "pipe"],
      });
      execSync(`${IT2API} activate window ${match.windowId}`, {
        stdio: ["pipe", "pipe", "pipe"],
      });
    }
    // Also bring iTerm to front
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
