import chalk from "chalk";
import type { Project } from "../types.js";
import { focusIterm } from "./iterm.js";
import { focusChrome } from "./chrome.js";
import { focusGenericWindows } from "./generic.js";

export function orchestrateFocus(project: Project): void {
  const results: string[] = [];

  // 1. iTerm — match by project directory
  if (focusIterm(project.path)) {
    results.push("iTerm");
  }

  // 2. Chrome — match by URL patterns
  if (focusChrome(project.signatures.url_patterns)) {
    results.push("Chrome");
  }

  // 3. Generic — match window titles containing project name
  const genericApps = focusGenericWindows(project.name);
  results.push(...genericApps);

  if (results.length) {
    console.log(
      chalk.dim(`  Focused: ${[...new Set(results)].join(", ")}`)
    );
  } else {
    console.log(chalk.dim("  No matching windows found"));
  }
}
