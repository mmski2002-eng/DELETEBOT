import os
import sys
import json
from dotenv import load_dotenv
import google.generativeai as genai

from known_slots import KNOWN_SLOTS
from tools import fetch_source, parse_storage_layout as _parse_storage_layout

load_dotenv()

ETHERSCAN_API_KEY = os.environ["ETHERSCAN_API_KEY"]
GEMINI_API_KEY = os.environ["GEMINI_API_KEY"]

genai.configure(api_key=GEMINI_API_KEY)

KNOWN_SLOTS_FORMATTED = "\n".join(
    f"  {slot} => {desc}" for slot, desc in KNOWN_SLOTS.items()
)

SYSTEM_PROMPT = f"""You are a smart contract security auditor specializing in storage slot collision vulnerabilities.
When given a contract address:
1) fetch its source code
2) parse storage layout
3) reason about whether any mapping's computed slot could collide with known library fixed slots.

Known fixed slots:
{KNOWN_SLOTS_FORMATTED}

Think step by step. Report collisions with: variable name, colliding slot, severity (Critical/High/Medium), explanation."""


def fetch_contract_source(address: str) -> str:
    """Fetch verified source code for a contract from Etherscan."""
    return fetch_source(address, ETHERSCAN_API_KEY)


def parse_storage_layout(source_code: str) -> str:
    """Parse state variables from Solidity source and return JSON list."""
    result = _parse_storage_layout(source_code)
    return json.dumps(result, indent=2)


TOOL_FUNCTIONS = {
    "fetch_contract_source": fetch_contract_source,
    "parse_storage_layout": parse_storage_layout,
}

TOOLS = [
    {
        "function_declarations": [
            {
                "name": "fetch_contract_source",
                "description": "Fetch verified Solidity source code for a contract address from Etherscan.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "address": {
                            "type": "string",
                            "description": "Ethereum contract address (0x...)",
                        }
                    },
                    "required": ["address"],
                },
            },
            {
                "name": "parse_storage_layout",
                "description": "Parse state variable declarations from Solidity source code. Returns JSON list of {name, type, base_slot_index}.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "source_code": {
                            "type": "string",
                            "description": "Full Solidity source code string.",
                        }
                    },
                    "required": ["source_code"],
                },
            },
        ]
    }
]


def run_agent(contract_address: str):
    model = genai.GenerativeModel(
        model_name="gemini-2.0-flash-lite",
        system_instruction=SYSTEM_PROMPT,
        tools=TOOLS,
    )

    messages = [
        {"role": "user", "parts": [f"Audit this contract for storage slot collisions: {contract_address}"]},
    ]

    print(f"[*] Auditing {contract_address} ...\n")

    while True:
        response = model.generate_content(messages)
        candidate = response.candidates[0]
        content = candidate.content

        # Collect tool calls from all parts
        tool_calls = [p for p in content.parts if hasattr(p, "function_call") and p.function_call.name]

        if not tool_calls:
            # Final answer — print text
            text_parts = [p.text for p in content.parts if hasattr(p, "text") and p.text]
            print("\n".join(text_parts))
            break

        # Append model turn
        messages.append({"role": "model", "parts": content.parts})

        # Execute each tool call and collect results
        tool_response_parts = []
        for part in tool_calls:
            fc = part.function_call
            fn_name = fc.name
            fn_args = dict(fc.args)

            print(f"[tool] {fn_name}({', '.join(f'{k}={repr(v)[:60]}' for k, v in fn_args.items())})")

            try:
                result = TOOL_FUNCTIONS[fn_name](**fn_args)
            except Exception as e:
                result = f"ERROR: {e}"

            tool_response_parts.append(
                genai.protos.Part(
                    function_response=genai.protos.FunctionResponse(
                        name=fn_name,
                        response={"result": result},
                    )
                )
            )

        messages.append({"role": "user", "parts": tool_response_parts})


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python agent.py <contract_address>")
        sys.exit(1)
    run_agent(sys.argv[1])
