import { readFile, writeFile, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { homedir } from "node:os";
import lockfile from "proper-lockfile";
import type { WorkstreamsState } from "../types.js";

const STATE_DIR = path.join(homedir(), ".workstreams");
const STATE_FILE = path.join(STATE_DIR, "state.json");

function emptyState(): WorkstreamsState {
  return {
    projects: {},
    current_focus: null,
  };
}

async function ensureStateDir(): Promise<void> {
  if (!existsSync(STATE_DIR)) {
    await mkdir(STATE_DIR, { recursive: true });
  }
}

async function ensureStateFile(): Promise<void> {
  await ensureStateDir();
  if (!existsSync(STATE_FILE)) {
    await writeFile(STATE_FILE, JSON.stringify(emptyState(), null, 2));
  }
}

export async function readState(): Promise<WorkstreamsState> {
  await ensureStateFile();
  const raw = await readFile(STATE_FILE, "utf-8");
  return JSON.parse(raw) as WorkstreamsState;
}

export async function writeState(state: WorkstreamsState): Promise<void> {
  await ensureStateFile();
  await writeFile(STATE_FILE, JSON.stringify(state, null, 2));
}

export async function withState(
  fn: (state: WorkstreamsState) => WorkstreamsState | Promise<WorkstreamsState>
): Promise<WorkstreamsState> {
  await ensureStateFile();

  const release = await lockfile.lock(STATE_FILE, {
    retries: { retries: 3, minTimeout: 100, maxTimeout: 1000 },
  });

  try {
    const state = await readState();
    const updated = await fn(state);
    await writeState(updated);
    return updated;
  } finally {
    await release();
  }
}

export { STATE_DIR, STATE_FILE };
