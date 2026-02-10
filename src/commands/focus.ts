import chalk from "chalk";
import { withState, readState } from "../core/state.js";
import { detectProjectName } from "../core/detect.js";
import { scanProject } from "../core/scan.js";
import { orchestrateFocus, detectWindows, activateMatch } from "../focus/orchestrator.js";

export async function focusCommand(
  name?: string,
  options?: { window?: string; app?: string }
): Promise<void> {
  const projectName = name || (await detectProjectName());
  if (!projectName) {
    console.error(chalk.red("Could not detect project. Specify a name or run from a project directory."));
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

  // Rescan signatures before focusing so URL patterns etc. are up to date
  const freshSigs = await scanProject(project.path);

  const colorFn = chalk[project.color] || chalk.white;
  const now = new Date().toISOString();

  // Update state with fresh signatures
  const updated = await withState((s) => {
    s.current_focus = projectName;
    const p = s.projects[projectName];
    p.signatures = freshSigs;
    if (p.status === "parked") {
      p.status = "active";
      p.parked_note = null;
      p.parked_at = null;
      p.history.push({ action: "unparked", at: now });
    }
    p.history.push({ action: "focused", at: now });
    return s;
  });

  console.log(`🎯 Focused on ${colorFn(projectName)}`);

  const targetProject = updated.projects[projectName];

  // If --window or --app specified, use selective activation
  if (options?.window || options?.app) {
    const matches = detectWindows(targetProject);

    if (matches.length === 0) {
      console.log(chalk.dim("  No matching windows found"));
      return;
    }

    let toActivate = matches;

    // Filter by app if specified
    if (options.app) {
      const appFilter = options.app.toLowerCase();
      toActivate = toActivate.filter(
        (m) => m.app.toLowerCase() === appFilter
      );
      if (toActivate.length === 0) {
        console.log(chalk.dim(`  No ${options.app} windows found`));
        return;
      }
    }

    // Select by index if specified
    if (options.window) {
      const idx = parseInt(options.window, 10);
      if (isNaN(idx) || idx < 1 || idx > toActivate.length) {
        console.error(
          chalk.red(
            `Invalid window index ${options.window}. Use 1-${toActivate.length}.`
          )
        );
        process.exit(1);
      }
      toActivate = [toActivate[idx - 1]];
    }

    const activated: string[] = [];
    for (const match of toActivate) {
      if (activateMatch(match)) {
        activated.push(match.app);
      }
    }

    if (activated.length) {
      console.log(
        chalk.dim(`  Focused: ${[...new Set(activated)].join(", ")}`)
      );
    }
    return;
  }

  // Default: raise all matching windows
  orchestrateFocus(targetProject);
}
