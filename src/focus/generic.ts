import { execSync } from "node:child_process";
import type { GenericMatch } from "../types.js";

export function detectGenericWindows(projectName: string): GenericMatch[] {
  const script = `
    tell application "System Events"
      set matchLines to {}
      set allProcesses to every process whose background only is false
      repeat with proc in allProcesses
        set procName to name of proc
        try
          set wins to windows of proc
          repeat with w in wins
            set winTitle to name of w
            if winTitle contains "${projectName}" then
              set end of matchLines to procName & "||" & winTitle
            end if
          end repeat
        end try
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
      const [processName, ...titleParts] = line.split("||");
      return {
        app: processName,
        window_title: titleParts.join("||"),
        process_name: processName,
      };
    });
  } catch {
    return [];
  }
}

export function activateGenericWindow(match: GenericMatch): boolean {
  const script = `
    tell application "System Events"
      set frontmost of process "${match.process_name}" to true
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

export function focusGenericWindows(projectName: string): string[] {
  const matches = detectGenericWindows(projectName);
  if (matches.length === 0) return [];

  // Activate all matches and collect unique app names (preserves original behavior)
  const activated: string[] = [];
  for (const match of matches) {
    if (activateGenericWindow(match)) {
      activated.push(match.process_name);
    }
  }
  return [...new Set(activated)];
}
