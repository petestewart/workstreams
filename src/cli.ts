#!/usr/bin/env node

import { Command } from "commander";
import { addCommand } from "./commands/add.js";
import { listCommand } from "./commands/list.js";
import { focusCommand } from "./commands/focus.js";
import { parkCommand } from "./commands/park.js";
import { statusCommand } from "./commands/status.js";

const program = new Command();

program
  .name("ws")
  .description("Manage multiple concurrent software projects")
  .version("0.1.0");

program
  .command("add")
  .argument("[name]", "Project name (defaults to directory name)")
  .description("Register the current directory as a project")
  .action(addCommand);

program
  .command("list")
  .alias("ls")
  .description("Show all registered projects")
  .action(listCommand);

program
  .command("focus")
  .argument("[name]", "Project name (defaults to current project)")
  .description("Focus a project — bring its windows to the front")
  .action(focusCommand);

program
  .command("park")
  .argument("[message]", "Note about why you're parking")
  .description("Park the current project with an optional note")
  .action(parkCommand);

program
  .command("status")
  .alias("st")
  .description("Show detail for the current project")
  .action(statusCommand);

program.parse();
