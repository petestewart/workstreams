# Spec Planner - Implementation Prompt

Study @specs/README.md and PLAN.md

Work on the current task (the first task with status "[in_progress]" or "[pending]"). If none is marked as "[in_progress]" then determine what the most important or most logical task is to start on.

1. Find the first unchecked task (`[ ]`) in that task
2. Read any referenced specs before implementing
3. Implement the task and write tests to verify it works
4. Mark the task complete (`[x]`) in PLAN.md

When a task is complete:
1. Change its status to "[complete]"
2. Change the next task's status to "[in_progress]"
3. IMPORTANT: Commit changes with a message describing what was completed, then push your commit

## Rules

- **All verification items must pass** before marking a task complete
- **If new work is discovered**, add it to the appropriate task in PLAN.md
- **Read the relevant spec** before implementing any task
- **Write tests** for new functionality
- **Commit frequently** after completing tasks (if git is initialized)
