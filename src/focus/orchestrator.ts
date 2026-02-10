import chalk from "chalk";
import type { Project, WindowMatch } from "../types.js";
import { detectIterm, activateIterm } from "./iterm.js";
import { detectChrome, activateChrome } from "./chrome.js";
import { detectGenericWindows, activateGenericWindow } from "./generic.js";

export function detectWindows(project: Project): WindowMatch[] {
  const matches: WindowMatch[] = [];

  matches.push(...detectIterm(project.path));
  matches.push(...detectChrome(project.signatures.url_patterns));
  matches.push(...detectGenericWindows(project.name));

  return matches;
}

export function activateMatch(match: WindowMatch): boolean {
  if ("session_id" in match) {
    return activateIterm(match);
  }
  if ("url" in match) {
    return activateChrome(match);
  }
  return activateGenericWindow(match);
}

export function orchestrateFocus(project: Project): void {
  const matches = detectWindows(project);

  if (matches.length === 0) {
    console.log(chalk.dim("  No matching windows found"));
    return;
  }

  const activated: string[] = [];
  for (const match of matches) {
    if (activateMatch(match)) {
      activated.push(match.app);
    }
  }

  if (activated.length) {
    console.log(
      chalk.dim(`  Focused: ${[...new Set(activated)].join(", ")}`)
    );
  } else {
    console.log(chalk.dim("  No matching windows found"));
  }
}
