# Global instructions

- Never credit or mention AI in anything you produce — commits, PRs, Jira tickets, markdown, docs, code comments. No "Co-Authored-By", no "Generated with", no references to Claude, Anthropic, or model names. All work is authored solely by the user.
- Write for someone reading the current state of the work, not its history — git and the ticket already hold the story. Applies to code comments, commits, PRs, tickets and docs.
- Comment only what the code cannot say: a constraint or a why, one line, describing the state rather than the edit that produced it — `// single writer; the metrics thread reads without a lock`, not `// removed the old lock`. Match the comment density of the file around you.
- In PRs, tickets and docs, say what the thing does and how to verify it, in a few lines. When a line does not earn its place, leave it out.
- Treat the request as the full scope: deliver exactly what was asked, then stop. Produce only the artifacts the task names — a ticket, doc, test, script or refactor exists because it was requested, not because it seemed useful.
- When you spot an adjacent improvement or missing piece, name it in one line at the end and leave it undone until asked.
