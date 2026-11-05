#!/usr/bin/env python3
"""Render config/files/** into one text bundle for Secret Manager (see "Bundle format" below).

Standard library only. The rules are documented in config/README.md.

  ${NAME}            value of NAME in config/common.env (or an %include argument)
  ${secrets.NAME}    value of the GitHub repository secret NAME
  $${                a literal ${ as seen by the final consumer
  %include F A=v     inline config/files/F with fragment variables A=v   (F is a fragment)
  %% text            source-only comment, not written to the output

Which source becomes which output file is decided by the OUTPUTS table below. Files or folders
under config/files/ whose name starts with "_" are fragments and are never written out.
Full-line comments (first non-blank character '#') are copied verbatim, never expanded.
Output files whose name starts with ".env" are env files: substituted values get '$' -> '$$'
(Docker Compose escaping) and unsafe values are rejected.

Bundle format (plain text, so the deploy side needs only bash and base64 to read it):
  line 1:                    config-bundle v1
  then one line per file:    <output path> <base64 of the file content>

File modes are NOT part of the bundle. The script on the deploy side (apply-config.sh) decides
which paths may be written and with which mode.
"""
import argparse
import base64
import json
import os
import re
import sys
from pathlib import Path

# source file (under config/files/) -> output path (relative to the target directory).
# apply-config.sh has its own allowlist of output paths; keep the two in sync.
OUTPUTS = {
    "compose-project.env": ".env",
    ".env.cloudflared": ".env.cloudflared",
    ".env.egress-proxy": ".env.egress-proxy",
    ".env.fail2ban": ".env.fail2ban",
    ".env.vaultwarden": ".env.vaultwarden",
    "cloudflared/config.yml": "cloudflared/config.yml",
    "cloudflared/vault-tunnel-cred.json": "cloudflared/vault-tunnel-cred.json",
    "deploy-ids.env": "deploy-ids.env",  # UID/GID numbers for the deployment script (single source)
    "git-identity.env": "git-identity.env",  # data: apply-config.sh turns it into gitconfig.sh
    "cloudflare-values.env": "cloudflare-values.env",  # data: apply-config.sh substitutes it into fail2ban/action.d/cloudflare-iplist.tmpl.conf
    "fail2ban-values.env": "fail2ban-values.env",  # data: apply-config.sh substitutes it into fail2ban/jail.d/jail.tmpl.local and smtp-direct.tmpl.conf
    "vm-values.env": "vm-values.env",  # data: apply-config.sh substitutes it into cloud-config.tmpl.yaml
}

TOKEN = re.compile(r"\$\$\{|\$\{([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?)\}")
KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
INCLUDE_RE = re.compile(r"%include\s+([A-Za-z0-9_.-]+)((?:\s+\S+)*)")
FILL_ME = "__FILL_ME__"
MAX_BUNDLE_BYTES = 60_000  # Secret Manager allows 64 KiB per version


def env_problem(value):
    """Why a substituted value cannot be written safely into an env file (None if fine)."""
    if "\n" in value or "\r" in value:
        return "contains a newline (not allowed in an env file; use a non-env output file)"
    if value != value.strip():
        return "has leading or trailing whitespace"
    if value[:1] in ('"', "'"):
        return "starts with a quote character"
    if " #" in value:
        return "contains ' #', which starts a comment in env files"
    return None


class Renderer:
    def __init__(self, config_dir, secrets, dry_run):
        self.dir = Path(config_dir)
        self.files_dir = self.dir / "files"
        self.dry_run = dry_run
        self.errors = []
        self.warnings = []
        self.common_raw = {}
        self.cache = {}
        self.stack = []
        self.used_secret_values = set()
        self.secrets = {}
        for name, value in secrets.items():
            upper = name.upper()  # GitHub treats secret names case-insensitively
            if upper in self.secrets:
                self.err(f"GitHub secrets {name!r} and another secret differ only by case")
            self.secrets[upper] = value

    # ---- diagnostics (never include secret values) ----
    def err(self, msg):
        if msg not in self.errors:
            self.errors.append(msg)

    # ---- common.env ----
    def load_common(self):
        path = self.dir / "common.env"
        if not path.is_file():
            self.err(f"{path} not found")
            return
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            key, sep, value = line.partition("=")
            if not sep or not KEY_RE.match(key):
                self.err(f"common.env:{n}: expected KEY=VALUE")
                continue
            if key in self.common_raw:
                self.err(f"common.env:{n}: duplicate key {key}")
                continue
            self.common_raw[key] = value

    def get_common(self, key):
        if key in self.cache:
            return self.cache[key]
        if key in self.stack:
            self.err("common.env: reference cycle: " + " -> ".join(self.stack + [key]))
            return "", set()
        raw = self.common_raw[key]
        sink = set()
        if FILL_ME in raw:
            self.err(f"common.env: {key} is still {FILL_ME}; fill it in (or leave it empty on purpose)")
            value = ""
        else:
            self.stack.append(key)
            value = self.expand(raw, {}, f"common.env:{key}", False, sink)
            self.stack.pop()
        sink.add(key)
        self.cache[key] = (value, sink)
        return value, sink

    # ---- substitution ----
    def value_of(self, name, local, where, sink):
        if "." in name:
            ns, key = name.split(".", 1)
            if ns != "secrets":
                self.err(f"{where}: unknown namespace in ${{{name}}} (only 'secrets.' is supported)")
                return None
            sink.add(name)
            value = self.secrets.get(key.upper())
            if value:
                self.used_secret_values.add(value)
                return value
            if self.dry_run:
                return f"<secret:{key}>"
            self.err(f"{where}: GitHub secret {key} is missing or empty")
            return None
        if name in local:
            value, deps = local[name]
            sink |= deps
            return value
        if name in self.common_raw:
            value, deps = self.get_common(name)
            sink |= deps
            return value
        self.err(f"{where}: ${{{name}}} is not defined in common.env")
        return None

    def expand(self, text, local, where, env_mode, sink):
        def repl(match):
            name = match.group(1)
            if name is None:  # $${
                return "$${" if env_mode else "${"
            value = self.value_of(name, local, where, sink)
            if value is None:
                return ""
            if env_mode:
                problem = env_problem(value)
                if problem:
                    self.err(f"{where}: value of ${{{name}}} {problem}")
                    return ""
                value = value.replace("$", "$$")
            return value

        return TOKEN.sub(repl, text)

    # ---- files ----
    def render_source(self, src, local, env_mode, sink, stack):
        out = []
        for n, line in enumerate(src.read_text(encoding="utf-8").splitlines(), 1):
            where = f"{src.relative_to(self.files_dir).as_posix()}:{n}"  # full path: names repeat across folders
            stripped = line.strip()
            if stripped.startswith("%%"):  # source-only comment, not emitted
                continue
            if stripped.startswith("%include"):
                m = INCLUDE_RE.fullmatch(stripped)
                if not m:
                    self.err(f"{where}: expected '%include FRAGMENT [NAME=value ...]'")
                    continue
                name = m.group(1)
                frag = self.files_dir / name
                if not frag.is_file():
                    self.err(f"{where}: fragment {name} not found in config/files/")
                    continue
                if name in stack:
                    self.err(f"{where}: %include cycle through {name}")
                    continue
                new_local = {}
                for token in m.group(2).split():
                    key, sep, raw = token.partition("=")
                    if not sep or not KEY_RE.match(key):
                        self.err(f"{where}: bad %include argument (expected NAME=value)")
                        continue
                    arg_sink = set()
                    new_local[key] = (self.expand(raw, local, where, False, arg_sink), arg_sink)
                out.extend(self.render_source(frag, new_local, env_mode, sink, stack + [name]))
                continue
            if stripped.startswith("#"):
                out.append(line)
                continue
            out.append(self.expand(line, local, where, env_mode, sink))
        return out

    def run(self):
        self.load_common()
        if not self.files_dir.is_dir():
            self.err(f"{self.files_dir} not found")
            return {}, {}
        outputs = list(OUTPUTS.values())
        if len(set(outputs)) != len(outputs):
            self.err("OUTPUTS in render.py maps two sources to the same output path")
        if any(re.search(r"\s", p) for p in outputs):
            self.err("OUTPUTS in render.py: output paths must not contain whitespace")
        on_disk = set()
        for path in self.files_dir.rglob("*"):
            rel = path.relative_to(self.files_dir)
            if path.is_file() and not any(part.startswith("_") for part in rel.parts):
                on_disk.add(rel.as_posix())
        for name in sorted(on_disk - set(OUTPUTS)):
            self.err(f"config/files/{name} is not listed in OUTPUTS in scripts/render.py")
        files, usage = {}, {}
        for source, out_path in sorted(OUTPUTS.items(), key=lambda kv: kv[1]):
            src = self.files_dir / source
            if not src.is_file():
                self.err(f"OUTPUTS lists {source}, which is not in config/files/")
                continue
            sink = set()
            env_mode = os.path.basename(out_path).startswith(".env")
            lines = self.render_source(src, {}, env_mode, sink, [])
            files[out_path] = "\n".join(lines) + "\n"
            usage[out_path] = sink
        used = set().union(*usage.values()) if usage else set()
        for key in self.common_raw:
            if key not in used:
                self.warnings.append(f"common.env: {key} is not used by any file")
        return files, usage


def build_report(usage, common_keys):
    """Markdown matrix of where each secret and shared value ends up (names only, never values)."""
    by_name = {}
    for path, names in usage.items():
        for name in names:
            by_name.setdefault(name, []).append(path)
    lines = ["## Config audit", "", "### Secrets", ""]
    secrets = sorted(n for n in by_name if n.startswith("secrets."))
    lines += [f"- `{n}` -> {', '.join(f'`{p}`' for p in sorted(by_name[n]))}" for n in secrets] or ["- none"]
    lines += ["", "### Shared values (common.env)", ""]
    shared = sorted(n for n in by_name if n in common_keys)
    lines += [f"- `{n}` -> {', '.join(f'`{p}`' for p in sorted(by_name[n]))}" for n in shared] or ["- none"]
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default="config", help="config directory (default: config)")
    ap.add_argument("--out", help="write the text bundle here (mode 600)")
    ap.add_argument("--secrets-env", default="ALL_SECRETS",
                    help="environment variable holding a JSON object of secrets (default: ALL_SECRETS)")
    ap.add_argument("--dry-run", action="store_true",
                    help="structure check only: missing secrets are replaced by <secret:NAME>")
    ap.add_argument("--mask", action="store_true", help="print ::add-mask:: lines for used secrets (GitHub Actions)")
    args = ap.parse_args()

    try:
        secrets = json.loads(os.environ.get(args.secrets_env) or "{}")
        if not isinstance(secrets, dict):
            raise ValueError("not an object")
        secrets = {str(k): str(v) for k, v in secrets.items()}
    except ValueError as exc:
        print(f"error: ${args.secrets_env} is not a JSON object ({exc})", file=sys.stderr)
        return 2

    r = Renderer(args.config, secrets, args.dry_run)
    files, usage = r.run()

    if args.mask:  # before anything else is printed
        for value in sorted(r.used_secret_values):
            for part in value.splitlines():
                if part.strip():
                    print(f"::add-mask::{part}")

    lines = ["config-bundle v1"]
    for path, content in sorted(files.items()):
        lines.append(f"{path} {base64.b64encode(content.encode('utf-8')).decode('ascii')}")
    payload = "\n".join(lines) + "\n"
    if len(payload.encode()) > MAX_BUNDLE_BYTES:
        r.err(f"bundle is {len(payload.encode())} bytes; Secret Manager allows 65536 per version")

    gha = os.environ.get("GITHUB_ACTIONS") == "true"
    for w in r.warnings:
        print(f"::warning::{w}" if gha else f"warning: {w}")
    for e in r.errors:
        print(f"::error::{e}" if gha else f"error: {e}")

    report = build_report(usage, set(r.common_raw))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write(report)
    else:
        print(report)

    if r.errors:
        return 1
    if args.out:
        fd = os.open(args.out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(payload)
    print(f"Rendered {len(files)} files ({len(payload)} bytes).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
