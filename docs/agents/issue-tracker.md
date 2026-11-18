# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues in `Baro007/freenet`. Use the `gh` CLI for all operations and pass `--repo Baro007/freenet` while the root Git metadata is being repaired.

## Conventions

- **Create an issue**: `gh issue create --repo Baro007/freenet --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --repo Baro007/freenet --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --repo Baro007/freenet --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --repo Baro007/freenet --body "..."`.
- **Apply or remove labels**: `gh issue edit <number> --repo Baro007/freenet --add-label "..."` or `--remove-label "..."`.
- **Close an issue**: `gh issue close <number> --repo Baro007/freenet --comment "..."`.

Once the root Git repository has a valid GitHub remote, `gh` may infer the repository automatically. Explicit `--repo Baro007/freenet` remains valid and avoids ambiguity.

## Pull requests as a triage surface

**PRs as a request surface: no.** External pull requests do not enter the issue triage state machine. Review PRs separately as code contributions.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either. Resolve with `gh pr view 42 --repo Baro007/freenet` and fall back to `gh issue view 42 --repo Baro007/freenet`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue in `Baro007/freenet`.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --repo Baro007/freenet --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes, Decisions-so-far, and Fog sections.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue. Where sub-issues are unavailable, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Use a `wayfinder:<type>` label where type is `research`, `prototype`, `grilling`, or `task`.
- **Blocking**: use GitHub's native issue dependencies. Add an edge with `gh api --method POST repos/Baro007/freenet/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the numeric database ID from `gh api repos/Baro007/freenet/issues/<n> --jq .id`. If dependencies are unavailable, use a `Blocked by: #<n>, #<n>` line at the top of the child body.
- **Frontier query**: list the map's open children, then drop any with an open blocker or assignee. The first remaining child in map order is the frontier.
- **Claim**: `gh issue edit <n> --repo Baro007/freenet --add-assignee @me`. Claiming is the session's first tracker write.
- **Resolve**: comment with the answer, close the child, then append a context pointer to the map's Decisions-so-far section.
