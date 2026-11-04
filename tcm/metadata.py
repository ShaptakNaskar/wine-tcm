#!/usr/bin/env python3
"""Read the Steam build ID and the source revisions embedded in Proton."""
import re
import sys
from pathlib import Path


def read_vdf(text):
    tokens = iter(re.findall(r'"((?:[^"\\]|\\.)*)"|([{}])', text))

    def quoted(value):
        return re.sub(r'\\(["\\])', r'\1', value)

    def object_body():
        result = {}
        while True:
            key, brace = next(tokens)
            if brace == "}":
                return result
            if brace:
                raise ValueError("Invalid VDF key")
            value, brace = next(tokens)
            if brace == "}":
                raise ValueError("Invalid VDF value")
            result[quoted(key)] = object_body() if brace == "{" else quoted(value)

    name, brace = next(tokens)
    if brace or next(tokens) != ("", "{"):
        raise ValueError("Invalid VDF root")
    return {quoted(name): object_body()}


def write_vdf(data, indent=""):
    def quote(text):
        return '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'

    lines = []
    for key, value in data.items():
        if isinstance(value, dict):
            lines.extend([indent + quote(key), indent + "{", write_vdf(value, indent + "\t"), indent + "}"])
        else:
            lines.append(indent + quote(key) + "\t\t" + quote(value))
    return "\n".join(lines)


def build_id(text, channel):
    start = re.search(r'^\s*"1493710"\s*$', text, re.MULTILINE)
    if not start:
        raise ValueError("Steam did not return Proton Experimental app info")
    result = read_vdf(text[start.start():])["1493710"]["depots"]["branches"][channel]["buildid"]
    if not result.isdecimal():
        raise ValueError("Invalid Steam build ID")
    return result


def revisions(text):
    match = re.fullmatch(r'\d+ (experimental\S+)-p([0-9a-f]{6,40})-w([0-9a-f]{6,40})-d\S+\s*', text)
    if not match:
        raise ValueError("Unrecognized Proton version; refusing to mix Wine revisions")
    return match.group(2), match.group(3)


def sync_manifest(original, downloaded):
    current = read_vdf(original)
    previous, latest = current["AppState"], read_vdf(downloaded)["AppState"]
    if previous["appid"] != "1493710" or latest["appid"] != "1493710":
        raise ValueError("Expected Proton Experimental app manifests")
    for key in ("buildid", "LastUpdated", "SizeOnDisk", "InstalledDepots", "StateFlags", "StagingSize", "UpdateResult", "UserConfig", "MountedConfig"):
        previous[key] = latest[key]
    previous["TargetBuildID"] = latest["buildid"]
    return write_vdf(current) + "\n"


if __name__ == "__main__":
    mode, filename, *args = sys.argv[1:]
    content = Path(filename).read_text()
    if mode == "build-id":
        print(build_id(content, args[0]))
    elif mode == "revisions":
        print(*revisions(content))
    elif mode == "sync-manifest":
        print(sync_manifest(content, Path(args[0]).read_text()), end="")
    else:
        raise SystemExit("Expected build-id or revisions")
