"""GSM8K prompt transform and deterministic rewards for the bundled GRPO recipes.

Axolotl imports this module from the working directory. Keep it next to the YAML
and launch from that directory (or explicitly add it to PYTHONPATH). This is a
simple exact-numeric reward, not a general mathematical equivalence checker.
"""

from decimal import Decimal
import re


_FINAL_ANSWER = re.compile(
    r"(?:^|\n)####\s*([+-]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?)\s*\Z"
)


def prompt_transform(cfg, *args, **kwargs):
    """Axolotl's native RL transform factory: no gold answer enters the prompt."""
    def transform(example, tokenizer=None):
        return {
            "prompt": [
                {
                    "role": "system",
                    "content": (
                        "Solve the math problem step by step. Put the final numerical "
                        "answer alone on the last line, prefixed by ####."
                    ),
                },
                {"role": "user", "content": example["question"]},
            ],
            "answer": example["answer"].split("####")[-1].strip().replace(",", ""),
        }

    return transform, {"remove_columns": ["question"]}


def _final_answer(completion):
    # TRL supplies chat completions for conversational prompts; also support
    # plain text if a user switches this recipe to a non-conversational prompt.
    text = completion if isinstance(completion, str) else completion[0]["content"]
    match = _FINAL_ANSWER.search(text)
    return match.group(1).replace(",", "") if match else None


def accuracy_reward(completions, answer, **kwargs):
    """Reward only the final formatted numeric answer, never intermediate numbers."""
    rewards = []
    for completion, expected in zip(completions, answer, strict=True):
        predicted = _final_answer(completion)
        correct = predicted is not None and Decimal(predicted) == Decimal(expected)
        rewards.append(float(correct))
    return rewards


def format_reward(completions, **kwargs):
    """Small shaping reward for an unambiguous final-answer line."""
    return [float(_final_answer(completion) is not None) for completion in completions]
