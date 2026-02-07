import chalk from "chalk";
import { readState } from "../core/state.js";
import { detectProjectName } from "../core/detect.js";

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

export async function statusCommand(): Promise<void> {
  const projectName = await detectProjectName();
  if (!projectName) {
    console.error(chalk.red("Could not detect project from current directory."));
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
  const isFocused = state.current_focus === project.name;

  console.log(colorFn.bold(project.name));
  console.log(chalk.dim("─".repeat(40)));
  console.log(`  Path:     ${project.path}`);
  console.log(
    `  Status:   ${project.status}${isFocused ? chalk.bold(" (current focus)") : ""}`
  );

  if (project.parked_note) {
    console.log(`  Note:     ${chalk.dim(`"${project.parked_note}"`)}`);
  }

  // Signatures
  console.log();
  console.log(chalk.bold("  Signatures"));
  if (project.signatures.git_remote) {
    console.log(`    Remote:   ${project.signatures.git_remote}`);
  }
  if (project.signatures.ports.length) {
    console.log(`    Ports:    ${project.signatures.ports.join(", ")}`);
  }
  if (project.signatures.database) {
    console.log(`    Database: ${project.signatures.database}`);
  }
  if (project.signatures.url_patterns.length) {
    console.log(`    URLs:     ${project.signatures.url_patterns.join(", ")}`);
  }

  // History (last 5)
  if (project.history.length) {
    console.log();
    console.log(chalk.bold("  Recent History"));
    const recent = project.history.slice(-5).reverse();
    for (const entry of recent) {
      const time = timeAgo(entry.at);
      let line = `    ${entry.action.padEnd(10)} ${chalk.dim(time)}`;
      if (entry.note) {
        line += ` — ${chalk.dim(`"${entry.note}"`)}`;
      }
      console.log(line);
    }
  }
}
