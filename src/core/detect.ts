import { execSync } from "node:child_process";
import path from "node:path";
import { readState } from "./state.js";

export function detectGitRoot(cwd: string = process.cwd()): string | null {
  try {
    const root = execSync("git rev-parse --show-toplevel", {
      cwd,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
    return root;
  } catch {
    return null;
  }
}

export async function detectProjectName(cwd: string = process.cwd()): Promise<string | null> {
  // 1. Try git root
  const gitRoot = detectGitRoot(cwd);
  if (gitRoot) {
    return path.basename(gitRoot);
  }

  // 2. Check if CWD is inside any registered project's path
  const state = await readState();
  const resolved = path.resolve(cwd);
  for (const project of Object.values(state.projects)) {
    const projectPath = path.resolve(project.path);
    if (resolved === projectPath || resolved.startsWith(projectPath + path.sep)) {
      return project.name;
    }
  }

  // 3. Fall back to directory name
  return path.basename(cwd);
}

export function detectGitRemote(cwd: string = process.cwd()): string | null {
  try {
    const remote = execSync("git remote get-url origin", {
      cwd,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
    // Normalize git@github.com:org/repo.git → github.com/org/repo
    return remote
      .replace(/^git@/, "")
      .replace(/^https?:\/\//, "")
      .replace(/:/, "/")
      .replace(/\.git$/, "");
  } catch {
    return null;
  }
}
