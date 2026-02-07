import chalk from "chalk";
import { readState, withState } from "../core/state.js";
import { detectGitRoot, detectProjectName } from "../core/detect.js";
import { scanProject } from "../core/scan.js";
import type { Project, ProjectColor } from "../types.js";

const COLOR_PALETTE: ProjectColor[] = [
  "red",
  "blue",
  "green",
  "yellow",
  "magenta",
  "cyan",
  "white",
];

function nextColor(usedColors: ProjectColor[]): ProjectColor {
  for (const color of COLOR_PALETTE) {
    if (!usedColors.includes(color)) return color;
  }
  // Cycle if all used
  return COLOR_PALETTE[usedColors.length % COLOR_PALETTE.length];
}

export async function addCommand(name?: string): Promise<void> {
  const cwd = process.cwd();
  const gitRoot = detectGitRoot(cwd);
  const projectPath = gitRoot || cwd;
  const projectName = name || (await detectProjectName(cwd)) || "unnamed";

  const signatures = await scanProject(projectPath);
  const usedColors = Object.values(
    (await readState()).projects
  ).map((p) => p.color);

  const project: Project = {
    name: projectName,
    path: projectPath,
    color: nextColor(usedColors),
    status: "active",
    parked_note: null,
    parked_at: null,
    signatures,
    history: [{ action: "added", at: new Date().toISOString() }],
  };

  await withState((state) => {
    if (state.projects[projectName]) {
      console.log(chalk.yellow(`Project "${projectName}" already exists. Updating.`));
    }
    state.projects[projectName] = project;
    if (!state.current_focus) {
      state.current_focus = projectName;
    }
    return state;
  });

  const colorFn = chalk[project.color] || chalk.white;
  console.log(
    `Added ${colorFn(projectName)} from ${projectPath}`
  );
  if (signatures.git_remote) {
    console.log(`  Remote: ${signatures.git_remote}`);
  }
  if (signatures.ports.length) {
    console.log(`  Ports: ${signatures.ports.join(", ")}`);
  }
  if (signatures.database) {
    console.log(`  Database: ${signatures.database}`);
  }
}
