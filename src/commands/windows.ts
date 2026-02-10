import chalk from "chalk";
import { readState } from "../core/state.js";
import { detectProjectName } from "../core/detect.js";
import { scanProject } from "../core/scan.js";
import { detectWindows } from "../focus/orchestrator.js";
import type { WindowMatch } from "../types.js";

function matchLabel(match: WindowMatch): string {
  if ("session_id" in match) {
    return match.title;
  }
  if ("url" in match) {
    return `${match.url} - ${match.title}`;
  }
  return match.window_title;
}

export async function windowsCommand(
  name?: string,
  options?: { json?: boolean }
): Promise<void> {
  const projectName = name || (await detectProjectName());
  if (!projectName) {
    console.error(
      chalk.red(
        "Could not detect project. Specify a name or run from a project directory."
      )
    );
    process.exit(1);
  }

  const state = await readState();
  const project = state.projects[projectName];

  if (!project) {
    console.error(
      chalk.red(`Project "${projectName}" not found. Run \`ws add\` first.`)
    );
    process.exit(1);
  }

  // Rescan signatures so URL patterns are current
  const freshSigs = await scanProject(project.path);
  const projectWithFreshSigs = { ...project, signatures: freshSigs };

  const matches = detectWindows(projectWithFreshSigs);

  if (options?.json) {
    console.log(JSON.stringify(matches, null, 2));
    return;
  }

  if (matches.length === 0) {
    console.log(chalk.dim("No matching windows found"));
    return;
  }

  for (let i = 0; i < matches.length; i++) {
    const match = matches[i];
    const idx = chalk.dim(`${(i + 1).toString().padStart(2)}`);
    const app = chalk.cyan(match.app.padEnd(10));
    const label = matchLabel(match);
    console.log(`  ${idx}  ${app} ${label}`);
  }
}
