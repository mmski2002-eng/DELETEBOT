from openai import OpenAI

client = OpenAI(
    base_url="https://integrate.api.nvidia.com/v1",
    api_key="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"
)

response = client.chat.completions.create(
    model="deepseek-ai/deepseek-v4-pro",
    messages=[
        {"role": "user", "content": "Привет! Ответь одним словом: работает?"}
    ],
    max_tokens=20
)

print(response.choices[0].message.content)