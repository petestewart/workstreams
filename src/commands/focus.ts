import chalk from "chalk";
import { withState, readState } from "../core/state.js";
import { detectProjectName } from "../core/detect.js";
import { orchestrateFocus } from "../focus/orchestrator.js";

export async function focusCommand(name?: string): Promise<void> {
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

  const colorFn = chalk[project.color] || chalk.white;
  const now = new Date().toISOString();

  // Update state
  await withState((s) => {
    s.current_focus = projectName;
    const p = s.projects[projectName];
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

  // Run AppleScript orchestration
  orchestrateFocus(project);
}
