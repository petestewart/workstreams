import chalk from "chalk";
import { readState, withState } from "../core/state.js";
import { detectProjectName } from "../core/detect.js";
import { scanProject } from "../core/scan.js";
import type { ProjectSignatures } from "../types.js";

function signaturesChanged(oldSigs: ProjectSignatures, newSigs: ProjectSignatures): boolean {
  return oldSigs.git_remote !== newSigs.git_remote
    || JSON.stringify(oldSigs.ports) !== JSON.stringify(newSigs.ports)
    || oldSigs.database !== newSigs.database
    || JSON.stringify(oldSigs.url_patterns) !== JSON.stringify(newSigs.url_patterns);
}

function printDiff(oldSigs: ProjectSignatures, newSigs: ProjectSignatures): void {
  if (oldSigs.git_remote !== newSigs.git_remote) {
    console.log(`  Remote: ${oldSigs.git_remote || "(none)"} → ${newSigs.git_remote || "(none)"}`);
  }
  if (JSON.stringify(oldSigs.ports) !== JSON.stringify(newSigs.ports)) {
    console.log(`  Ports: [${oldSigs.ports.join(", ") || "none"}] → [${newSigs.ports.join(", ") || "none"}]`);
  }
  if (oldSigs.database !== newSigs.database) {
    console.log(`  Database: ${oldSigs.database || "(none)"} → ${newSigs.database || "(none)"}`);
  }
  if (JSON.stringify(oldSigs.url_patterns) !== JSON.stringify(newSigs.url_patterns)) {
    console.log(`  URLs: [${oldSigs.url_patterns.join(", ") || "none"}] → [${newSigs.url_patterns.join(", ") || "none"}]`);
  }
}

export async function rescanCommand(name?: string, options?: { all?: boolean }): Promise<void> {
  if (options?.all) {
    const state = await readState();
    const names = Object.keys(state.projects);
    if (names.length === 0) {
      console.log(chalk.dim("No projects registered."));
      return;
    }

    for (const projName of names) {
      const project = state.projects[projName];
      const colorFn = chalk[project.color] || chalk.white;
      const newSigs = await scanProject(project.path);

      if (signaturesChanged(project.signatures, newSigs)) {
        console.log(`Rescanned ${colorFn(projName)}`);
        printDiff(project.signatures, newSigs);
      } else {
        console.log(`${colorFn(projName)} ${chalk.dim("— no changes")}`);
      }

      state.projects[projName].signatures = newSigs;
    }

    await withState(() => state);
    return;
  }

  const projectName = name || (await detectProjectName());
  if (!projectName) {
    console.error(chalk.red("Could not detect project. Specify a name or run from a project directory."));
    process.exit(1);
  }

  const state = await readState();
  const project = state.projects[projectName];

  if (!project) {
    console.error(chalk.red(`Project "${projectName}" not found. Run \`ws add\` first.`));
    process.exit(1);
  }

  const oldSigs = project.signatures;
  const newSigs = await scanProject(project.path);

  await withState((s) => {
    s.projects[projectName].signatures = newSigs;
    return s;
  });

  const colorFn = chalk[project.color] || chalk.white;
  console.log(`Rescanned ${colorFn(projectName)}`);

  if (signaturesChanged(oldSigs, newSigs)) {
    printDiff(oldSigs, newSigs);
  } else {
    console.log(chalk.dim("  No changes detected"));
  }
}
