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
  action: "added" | "focused" | "parked" | "unparked";
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
