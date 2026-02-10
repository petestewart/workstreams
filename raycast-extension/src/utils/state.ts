import { readFileSync, existsSync } from "node:fs";
import path from "node:path";
import { homedir } from "node:os";

export type ProjectStatus = "active" | "parked";

export type ProjectColor =
  | "red"
  | "blue"
  | "green"
  | "yellow"
  | "magenta"
  | "cyan"
  | "white";

export interface ProjectSignatures {
  git_remote: string | null;
  ports: number[];
  database: string | null;
  url_patterns: string[];
}

export interface HistoryEntry {
  action: string;
  note?: string;
  at: string;
}

export interface Project {
  name: string;
  path: string;
  color: ProjectColor;
  status: ProjectStatus;
  parked_note: string | null;
  parked_at: string | null;
  signatures: ProjectSignatures;
  history: HistoryEntry[];
}

export interface WorkstreamsState {
  projects: Record<string, Project>;
  current_focus: string | null;
}

const STATE_FILE = path.join(homedir(), ".workstreams", "state.json");

export function readState(): WorkstreamsState {
  if (!existsSync(STATE_FILE)) {
    return { projects: {}, current_focus: null };
  }
  const raw = readFileSync(STATE_FILE, "utf-8");
  return JSON.parse(raw) as WorkstreamsState;
}

// Window match types for detect/activate split

export interface ItermMatch {
  app: "iTerm";
  window_id: string;
  tab_id: string;
  session_id: string;
  title: string;
}

export interface ChromeMatch {
  app: "Chrome";
  window_index: number;
  tab_index: number;
  title: string;
  url: string;
}

export interface GenericMatch {
  app: string;
  window_title: string;
  process_name: string;
}

export type WindowMatch = ItermMatch | ChromeMatch | GenericMatch;

export function timeAgo(isoDate: string): string {
  const diff = Date.now() - new Date(isoDate).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}
