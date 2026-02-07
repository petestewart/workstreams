import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import type { ProjectSignatures } from "../types.js";
import { detectGitRemote } from "./detect.js";

export async function scanProject(
  projectPath: string
): Promise<ProjectSignatures> {
  const ports: number[] = [];
  const gitRemote = detectGitRemote(projectPath);

  // Scan .env for PORT variables
  const envFile = path.join(projectPath, ".env");
  if (existsSync(envFile)) {
    const env = await readFile(envFile, "utf-8");
    const portMatches = env.matchAll(/(?:PORT|port)\s*=\s*(\d+)/g);
    for (const match of portMatches) {
      ports.push(parseInt(match[1], 10));
    }
  }

  // Scan package.json for port in scripts
  const pkgFile = path.join(projectPath, "package.json");
  if (existsSync(pkgFile)) {
    const pkg = JSON.parse(await readFile(pkgFile, "utf-8"));
    if (pkg.scripts) {
      for (const script of Object.values(pkg.scripts) as string[]) {
        const portMatch = script.match(/(?:--port|PORT=|-p)\s*(\d{4,5})/);
        if (portMatch) {
          const p = parseInt(portMatch[1], 10);
          if (!ports.includes(p)) ports.push(p);
        }
      }
    }
  }

  // Scan docker-compose.yml for ports
  const composeFile = path.join(projectPath, "docker-compose.yml");
  if (existsSync(composeFile)) {
    const compose = await readFile(composeFile, "utf-8");
    const portMatches = compose.matchAll(
      /["']?(\d{4,5}):(\d{4,5})["']?/g
    );
    for (const match of portMatches) {
      const p = parseInt(match[1], 10);
      if (!ports.includes(p)) ports.push(p);
    }
  }

  // Detect database name from database.yml or .env
  let database: string | null = null;
  const dbYml = path.join(projectPath, "config", "database.yml");
  if (existsSync(dbYml)) {
    const dbConfig = await readFile(dbYml, "utf-8");
    const dbMatch = dbConfig.match(/database:\s*(\S+)/);
    if (dbMatch) database = dbMatch[1];
  }
  if (!database && existsSync(envFile)) {
    const env = await readFile(envFile, "utf-8");
    const dbMatch = env.match(/DATABASE_(?:URL|NAME)\s*=\s*(\S+)/);
    if (dbMatch) {
      // Extract db name from URL or direct name
      const val = dbMatch[1];
      const urlMatch = val.match(/\/([^/?]+)(?:\?|$)/);
      database = urlMatch ? urlMatch[1] : val;
    }
  }

  // Build URL patterns from git remote
  const urlPatterns: string[] = [];
  if (gitRemote) {
    urlPatterns.push(`${gitRemote}/**`);
  }
  // Add localhost patterns for detected ports
  for (const p of ports) {
    urlPatterns.push(`localhost:${p}/**`);
  }

  return {
    git_remote: gitRemote,
    ports,
    database,
    url_patterns: urlPatterns,
  };
}
