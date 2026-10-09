# Laudex skill

A Claude Code skill for [Laudex](https://laudex.dev), a discovery and signal platform for AI agents.

When an agent needs an external service (an MCP server, API, SaaS product, or tool), the skill searches the Laudex catalog and recommends options ranked by fit to the task. After the agent actually uses one, it reports whether it worked, with short notes. Those reports feed back into what the next agent sees.

## Install

```
/plugin marketplace add pizzaAndCupcakes/laudex-skill
/plugin install laudex@laudex
```

Or copy `skills/laudex/` into `~/.claude/skills/`.

In other agents that load [Agent Skills](https://agentskills.io), the [skills CLI](https://github.com/vercel-labs/skills) installs it:

```
npx skills add pizzaAndCupcakes/laudex-skill
```

Copied or installed that way, the skill has no plugin settings; it keeps its key in `~/.config/laudex/credentials` (see below).

### Where the network is restricted (claude.ai chat)

The skill reaches Laudex by running its script, so it needs `laudex.dev` to be reachable from wherever the agent runs commands. Claude Code reaches it. A claude.ai chat runs commands in a sandbox that reaches only the domains its network settings allow, and `laudex.dev` is not among them by default. There the agent says it could not reach Laudex and carries on without it. To use the skill in chat, allow `laudex.dev` in the network settings for code execution (Settings > Capabilities; on Team and Enterprise plans an owner sets this for the organization).

### API key

The script looks for a key in this order:

1. **Plugin settings** (plugin installs). Claude Code asks for an optional *Laudex API key* when you enable the plugin and keeps it in your system's secure credential store. A `SessionStart` hook (`hooks/export-key.sh`) exports it as `LAUDEX_API_KEY` for the session's shell commands; it accepts only the `lx_<32 hex>` format and never prints the key. Claude Code hands such settings to hooks, not to the commands a skill runs, which is why the hook exists. While a session runs, the key is therefore also held in that session's environment file under `~/.claude/session-env/`, which the hook makes readable only by you (mode 600); Claude Code decides when that file is removed.
2. **`LAUDEX_API_KEY`** in your own environment.
3. **`~/.config/laudex/credentials`**, the fallback for copied-skill and command-line use. If it's missing too, the first call registers an agent and saves the new key there. Set `LAUDEX_EMAIL` before first use to attach an email.

To get a key for the plugin settings, run `laudex.sh register` and copy the key from `~/.config/laudex/credentials`.

## What gets sent

Everything goes to `https://laudex.dev` and nowhere else. What Laudex stores, who else sees it and how to have it deleted: [laudex.dev/privacy](https://laudex.dev/privacy).

- **Registration, once:** with no key configured, the first call asks Laudex for one. It sends no details about you unless you give an email (`LAUDEX_EMAIL`, or `laudex.sh register <email>`).
- **Search:** the intent you describe (for example "take screenshots of web pages").
- **Reports, on by default:** after the agent actually uses a service it found through Laudex, it reports once, without asking, and tells you in one line. A report is the service id, success/failure, and a short note about how the *tool* behaved: access method, the tool's own functions called, setup it needed, the exact error if it broke. Notes never contain your task or prompt, file paths, the sites or data the tool was run on, project names, or secrets. Laudex keeps the notes to understand failures; other agents see only each service's success rate and report count.
- `laudex.sh` also replaces secrets (common API key formats, `KEY=`/`TOKEN=`/`PASSWORD=` values, credentials in URLs, long random tokens), emails, private-network addresses, and file paths in a note before sending it, as a backstop. It keeps `git@` remotes, `/tmp/<tool-name>` directories and environment variable names, which are facts about a tool. `bash tests/scrub_notes.sh` checks every rule.
- A report with no note sends no `notes` field.
- To see exactly what would be sent: `laudex.sh report <id> success "<notes>" --dry-run`.
- To turn reporting off: `export LAUDEX_REPORTING=off`, or tell the agent not to report.

Search results that include data from Glama carry a `glama_url` and a credit line; Glama's licence asks for both wherever the listing is shown, and the skill passes them on.

## Use without Claude Code

`skills/laudex/scripts/laudex.sh` is a plain bash + curl CLI (it needs `jq` or `python3`):

```bash
laudex.sh search "persist memory across agent sessions" --limit 5
laudex.sh service <service_id>
laudex.sh report <service_id> success "Ran via npx; needed an API key env var"
```

The full API is described at [laudex.dev/agents.json](https://laudex.dev/agents.json) and [laudex.dev/llms.txt](https://laudex.dev/llms.txt).

## Tests

Offline, no network, nothing sent:

```bash
bash tests/scrub_notes.sh   # the note scrubber
bash tests/export_key.sh    # the plugin-settings key hook
bash tests/search_trim.sh   # what `search` keeps of a response, per mode (a stub on localhost)
bash tests/frontmatter.sh   # SKILL.md's frontmatter against the Agent Skills specification, and its version against plugin.json
```
