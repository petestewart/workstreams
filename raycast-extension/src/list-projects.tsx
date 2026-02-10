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
import { readState, timeAgo, type Project, type WindowMatch, type ItermMatch } from "./utils/state";
import { activateMatch, activateItermMatch } from "./utils/activate";
import { useState, useCallback, useEffect } from "react";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { homedir } from "node:os";

const CLI_SCRIPT = path.join(homedir(), "Projects", "workstreams", "dist", "cli.js");

function wsExec(args: string[], cwd?: string) {
  return execFileSync(process.execPath, [CLI_SCRIPT, ...args], {
    encoding: "utf-8" as const,
    cwd,
    env: { ...process.env, HOME: homedir() },
  });
}

function getWindowMatches(projectName: string): WindowMatch[] {
  try {
    const output = wsExec(["windows", projectName, "--json"]);
    return JSON.parse(output) as WindowMatch[];
  } catch {
    return [];
  }
}

function windowIcon(match: WindowMatch): Icon {
  if ("session_id" in match) return Icon.Terminal;
  if ("url" in match) return Icon.Globe;
  return Icon.Window;
}

function windowTitle(match: WindowMatch): string {
  if ("session_id" in match) return match.title;
  if ("url" in match) return match.title;
  return match.window_title;
}

function windowSubtitle(match: WindowMatch): string {
  if ("url" in match) return match.url;
  if ("session_id" in match) return "iTerm";
  return match.process_name;
}

function WindowList({ project }: { project: Project }) {
  const [matches, setMatches] = useState<WindowMatch[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const results = getWindowMatches(project.name);
    setMatches(results);
    setIsLoading(false);
  }, [project.name]);

  return (
    <List
      navigationTitle={`${project.name} — Windows`}
      searchBarPlaceholder="Search windows..."
      isLoading={isLoading}
    >
      {matches.length === 0 && !isLoading ? (
        <List.EmptyView
          title="No Windows Found"
          description={`No matching windows detected for ${project.name}.`}
        />
      ) : (
        matches.map((match, idx) => (
          <List.Item
            key={idx}
            title={windowTitle(match)}
            subtitle={windowSubtitle(match)}
            icon={windowIcon(match)}
            accessories={[{ text: match.app }]}
            actions={
              <ActionPanel>
                <Action
                  title="Activate Window"
                  icon={Icon.Eye}
                  onAction={async () => {
                    await closeMainWindow();
                    activateMatch(match);
                  }}
                />
              </ActionPanel>
            }
          />
        ))
      )}
    </List>
  );
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
                // CLI updates state; its AppleScript won't activate windows from
                // Raycast's context, so we handle activation directly.
                wsExec(["focus", project.name]);
                const matches = getWindowMatches(project.name);
                const itermMatches = matches.filter((m): m is ItermMatch => "session_id" in m);
                if (itermMatches.length > 0) {
                  for (const m of itermMatches) activateItermMatch(m);
                } else {
                  execFileSync("open", ["-a", "iTerm"]);
                }
                for (const m of matches) {
                  if (!("session_id" in m)) activateMatch(m);
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
          <Action.Push
            title="Show Windows"
            icon={Icon.AppWindowList}
            target={<WindowList project={project} />}
            shortcut={{ modifiers: ["cmd", "shift"], key: "w" }}
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
