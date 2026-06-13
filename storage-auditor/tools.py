import re
import json
import requests


def fetch_source(address: str, api_key: str) -> str:
    url = "https://api.etherscan.io/api"
    params = {
        "module": "contract",
        "action": "getsourcecode",
        "address": address,
        "apikey": api_key,
    }
    resp = requests.get(url, params=params, timeout=15)
    resp.raise_for_status()
    data = resp.json()

    if data.get("status") != "1" or not data.get("result"):
        raise ValueError(f"Etherscan error: {data.get('message', 'unknown')}")

    result = data["result"][0]
    source = result.get("SourceCode", "")

    if not source:
        raise ValueError("No source code found for this address")

    # Multi-file JSON (wrapped in {{ }}) or plain JSON
    stripped = source.strip()
    if stripped.startswith("{{"):
        stripped = stripped[1:-1]  # remove outer braces
    try:
        parsed = json.loads(stripped)
        # Solidity standard JSON input format
        if "sources" in parsed:
            parts = []
            for fname, fdata in parsed["sources"].items():
                parts.append(f"// === {fname} ===\n{fdata.get('content', '')}")
            return "\n\n".join(parts)
        # Vyper format: dict of filename -> source
        if all(isinstance(v, str) for v in parsed.values()):
            parts = []
            for fname, content in parsed.items():
                parts.append(f"// === {fname} ===\n{content}")
            return "\n\n".join(parts)
    except (json.JSONDecodeError, AttributeError):
        pass

    return source


def parse_storage_layout(source_code: str) -> list[dict]:
    # Strip comments to avoid false positives
    source = re.sub(r"//[^\n]*", "", source_code)
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)

    # Match state variable declarations inside contracts
    # Captures: type (with generics/brackets), name
    VAR_RE = re.compile(
        r"""
        (?:^|\n)\s*
        (?:(?:public|private|internal|external|constant|immutable|override)\s+)*
        (
            mapping\s*\([^)]+\)(?:\s*\[[^\]]*\])* |  # mapping(...)
            \w[\w\.\[\]\s]*?                          # simple or array type
        )
        \s+
        (?:(?:public|private|internal|external|constant|immutable|override)\s+)*
        (\w+)
        \s*
        (?:=[^;]*)? ;
        """,
        re.VERBOSE,
    )

    SKIP_TYPES = {
        "function", "event", "modifier", "struct", "enum",
        "constructor", "fallback", "receive", "error",
        "import", "pragma", "using", "interface", "library", "contract",
        "abstract", "is", "returns", "return", "if", "for", "while",
        "emit", "require", "revert", "assembly", "bytes",
    }

    variables = []
    slot_index = 0

    for m in VAR_RE.finditer(source):
        raw_type = m.group(1).strip()
        name = m.group(2).strip()

        base_type = raw_type.split("(")[0].split("[")[0].strip().split()[-1]
        if base_type.lower() in SKIP_TYPES or not name or name[0].isupper():
            continue
        # Skip constants/immutables — they don't use storage
        ctx = source[max(0, m.start() - 20):m.end()]
        if "constant" in ctx or "immutable" in ctx:
            continue

        variables.append({
            "name": name,
            "type": raw_type,
            "base_slot_index": slot_index,
        })
        slot_index += 1

    return variables
