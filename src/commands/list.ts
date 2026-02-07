import chalk from "chalk";
import { readState } from "../core/state.js";
import type { Project } from "../types.js";

const STATUS_ICONS: Record<string, string> = {
  active: "",
  parked: "⏸",
};

function timeAgo(isoDate: string): string {
  const diff = Date.now() - new Date(isoDate).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

function colorDot(color: string): string {
  const dots: Record<string, string> = {
    red: "🔴",
    blue: "🔵",
    green: "🟢",
    yellow: "🟡",
    magenta: "🟣",
    cyan: "🔵",
    white: "⚪",
  };
  return dots[color] || "⚪";
}

export async function listCommand(): Promise<void> {
  const state = await readState();
  const projects = Object.values(state.projects);

  if (projects.length === 0) {
    console.log(chalk.dim("No projects registered. Run `ws add` in a project directory."));
    return;
  }

  // Sort: active first, then parked, alphabetical within group
  projects.sort((a, b) => {
    if (a.status !== b.status) return a.status === "active" ? -1 : 1;
    return a.name.localeCompare(b.name);
  });

  for (const project of projects) {
    const isFocused = state.current_focus === project.name;
    const colorFn = chalk[project.color] || chalk.white;
    const dot = colorDot(project.color);
    const name = colorFn(project.name.padEnd(20));
    const status = project.status.padEnd(8);

    let detail = "";
    if (isFocused) {
      detail = chalk.bold("(current focus)");
    } else if (project.parked_note) {
      detail = chalk.dim(`"${project.parked_note}"`);
      if (project.parked_at) {
        detail += chalk.dim(` (${timeAgo(project.parked_at)})`);
      }
    }

    console.log(`${dot} ${name} ${status} ${detail}`);
  }
}
