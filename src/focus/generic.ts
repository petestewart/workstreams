import { execSync } from "node:child_process";

export function focusGenericWindows(projectName: string): string[] {
  const script = `
    tell application "System Events"
      set matchedApps to {}
      set allProcesses to every process whose background only is false
      repeat with proc in allProcesses
        set procName to name of proc
        try
          set wins to windows of proc
          repeat with w in wins
            set winTitle to name of w
            if winTitle contains "${projectName}" then
              set frontmost of proc to true
              set end of matchedApps to procName
              exit repeat
            end if
          end repeat
        end try
      end repeat
      return matchedApps as text
    end tell
  `;

  try {
    const result = execSync("osascript", {
      input: script,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
    return result ? result.split(", ") : [];
  } catch {
    return [];
  }
}
