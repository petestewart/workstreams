import {
  Action,
  ActionPanel,
  closeMainWindow,
  Color,
  Icon,
  List,
  showToast,
  Toast,
} from "@raycast/api";
import { readState, timeAgo, type Project } from "./utils/state";
import { useState, useCallback } from "react";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { homedir } from "node:os";

const CLI_SCRIPT = path.join(homedir(), "Projects", "workstreams", "dist", "cli.js");
const IT2API = "/Applications/iTerm.app/Contents/Resources/utilities/it2api";

function wsExec(args: string[], cwd?: string) {
  return execFileSync(process.execPath, [CLI_SCRIPT, ...args], {
    encoding: "utf-8" as const,
    cwd,
    env: { ...process.env, HOME: homedir() },
  });
}

function focusItermTab(projectPath: string): boolean {
  try {
    // Get hierarchy from it2api
    const hierarchy = execFileSync(IT2API, ["show-hierarchy"], { encoding: "utf-8" as const });

    // Parse: map session ID → { tabId, windowId }
    const sessions = new Map<string, { tabId: string; windowId: string }>();
    let curWindow = "";
    let curTab = "";
    for (const line of hierarchy.split("\n")) {
      const wm = line.match(/^Window id=(\S+)/);
      if (wm) { curWindow = wm[1]; continue; }
      const tm = line.match(/^\s+Tab id=(\S+)/);
      if (tm) { curTab = tm[1]; continue; }
      const sm = line.match(/Session .+ id=(\S+)/);
      if (sm) sessions.set(sm[1], { tabId: curTab, windowId: curWindow });
    }

    // Get each session's tty via AppleScript
    const ttyScript = `tell application "iTerm"
set output to ""
repeat with w in windows
  repeat with t in tabs of w
    repeat with s in sessions of t
      set output to output & (id of s) & "=" & (tty of s) & linefeed
    end repeat
  end repeat
end repeat
return output
end tell`;

    const ttyOutput = execFileSync("/usr/bin/osascript", {
      input: ttyScript,
      encoding: "utf-8" as const,
    }).trim();

    // Match tty → cwd via lsof, find the one matching projectPath
    for (const line of ttyOutput.split("\n")) {
      const eq = line.indexOf("=");
      if (eq < 0) continue;
      const sessionId = line.slice(0, eq).trim();
      const tty = line.slice(eq + 1).trim();
      const info = sessions.get(sessionId);
      if (!info || !tty) continue;

      try {
        const ttyName = path.basename(tty);
        const psOut = execFileSync("/bin/ps", ["-t", ttyName, "-o", "pid=,comm="], { encoding: "utf-8" as const });
        const shellLine = psOut.split("\n").find((l) => /zsh|bash|fish/.test(l));
        const shellPid = shellLine?.trim().split(/\s+/)[0];
        if (!shellPid) continue;

        const lsofOut = execFileSync("/usr/sbin/lsof", ["-a", "-p", shellPid, "-d", "cwd", "-Fn"], { encoding: "utf-8" as const });
        const cwdLine = lsofOut.split("\n").find((l) => l.startsWith("n"));
        const cwd = cwdLine?.slice(1);

        if (cwd && cwd.startsWith(projectPath)) {
          execFileSync(IT2API, ["activate", "tab", info.tabId]);
          execFileSync(IT2API, ["activate", "window", info.windowId]);
          execFileSync("/usr/bin/osascript", { input: 'tell application "iTerm" to activate' });
          return true;
        }
      } catch { continue; }
    }
  } catch { /* it2api not available */ }
  return false;
}

const COLOR_MAP: Record<string, Color> = {
  red: Color.Red,
  blue: Color.Blue,
  green: Color.Green,
  yellow: Color.Yellow,
  magenta: Color.Magenta,
  cyan: Color.Blue,
  white: Color.PrimaryText,
};

function ProjectItem({
  project,
  isFocused,
  onRefresh,
}: {
  project: Project;
  isFocused: boolean;
  onRefresh: () => void;
}) {
  const color = COLOR_MAP[project.color] || Color.PrimaryText;
  const lastActivity = project.history.length
    ? timeAgo(project.history[project.history.length - 1].at)
    : "";

  const subtitle = isFocused
    ? "current focus"
    : project.parked_note
      ? `"${project.parked_note}"`
      : project.status;

  return (
    <List.Item
      title={project.name}
      subtitle={subtitle}
      icon={{ source: Icon.Circle, tintColor: color }}
      accessories={[{ text: lastActivity }]}
      actions={
        <ActionPanel>
          <Action
            title="Focus Project"
            icon={Icon.Eye}
            onAction={async () => {
              try {
                await closeMainWindow();
                // Update state (no AppleScript orchestration needed)
                wsExec(["focus", project.name]);
                // Switch iTerm tab directly via it2api + lsof
                if (!focusItermTab(project.path)) {
                  execFileSync("open", ["-a", "iTerm"]);
                }
              } catch (error) {
                await showToast({
                  style: Toast.Style.Failure,
                  title: "Failed to focus",
                  message: String(error),
                });
              }
            }}
          />
          <Action
            title="Park Project"
            icon={Icon.Pause}
            shortcut={{ modifiers: ["cmd", "shift"], key: "p" }}
            onAction={async () => {
              try {
                wsExec(["park"], project.path);
                await showToast({
                  style: Toast.Style.Success,
                  title: `Parked ${project.name}`,
                });
                onRefresh();
              } catch (error) {
                await showToast({
                  style: Toast.Style.Failure,
                  title: "Failed to park",
                  message: String(error),
                });
              }
            }}
          />
          <Action
            title="Open in Terminal"
            icon={Icon.Terminal}
            shortcut={{ modifiers: ["cmd"], key: "o" }}
            onAction={() => {
              execFileSync("open", ["-a", "iTerm", project.path]);
            }}
          />
          <Action.ShowInFinder title="Show in Finder" path={project.path} />
        </ActionPanel>
      }
    />
  );
}

export default function Command() {
  const [refreshKey, setRefreshKey] = useState(0);
  const onRefresh = useCallback(() => setRefreshKey((k) => k + 1), []);

  let state;
  try {
    state = readState();
  } catch {
    return (
      <List>
        <List.EmptyView
          title="No Workstreams State"
          description="Run `ws add` in a project directory to get started."
        />
      </List>
    );
  }

  const projects = Object.values(state.projects);

  if (projects.length === 0) {
    return (
      <List>
        <List.EmptyView
          title="No Projects"
          description="Run `ws add` in a project directory to register it."
        />
      </List>
    );
  }

  // Sort: focused first, then active, then parked
  const sorted = [...projects].sort((a, b) => {
    if (state.current_focus === a.name) return -1;
    if (state.current_focus === b.name) return 1;
    if (a.status !== b.status) return a.status === "active" ? -1 : 1;
    return a.name.localeCompare(b.name);
  });

  const active = sorted.filter((p) => p.status === "active");
  const parked = sorted.filter((p) => p.status === "parked");

  return (
    <List searchBarPlaceholder="Search projects...">
      {active.length > 0 && (
        <List.Section title="Active">
          {active.map((project) => (
            <ProjectItem
              key={project.name}
              project={project}
              isFocused={state.current_focus === project.name}
              onRefresh={onRefresh}
            />
          ))}
        </List.Section>
      )}
      {parked.length > 0 && (
        <List.Section title="Parked">
          {parked.map((project) => (
            <ProjectItem
              key={project.name}
              project={project}
              isFocused={false}
              onRefresh={onRefresh}
            />
          ))}
        </List.Section>
      )}
    </List>
  );
}
