import chalk from "chalk";
import { readState, withState } from "../core/state.js";
import { detectProjectName } from "../core/detect.js";

export async function parkCommand(message?: string): Promise<void> {
  const projectName = await detectProjectName();
  if (!projectName) {
    console.error(chalk.red("Could not detect project from current directory."));
    process.exit(1);
  }

  const now = new Date().toISOString();

  await withState((state) => {
    const project = state.projects[projectName];
    if (!project) {
      console.error(
        chalk.red(`Project "${projectName}" not found. Run \`ws add\` first.`)
      );
      process.exit(1);
    }

    project.status = "parked";
    project.parked_note = message || null;
    project.parked_at = now;
    project.history.push({
      action: "parked",
      note: message,
      at: now,
    });

    if (state.current_focus === projectName) {
      state.current_focus = null;
    }

    return state;
  });

  const colorFn = chalk[
    (await readState()).projects[projectName]?.color || "white"
  ] || chalk.white;

  console.log(`⏸  Parked ${colorFn(projectName)}`);
  if (message) {
    console.log(chalk.dim(`   "${message}"`));
  }
}
