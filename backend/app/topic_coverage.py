def topic_coverage_instruction(topic: str, quantity: int, offset: int) -> str:
    raw = topic.split(":", 1)[-1] if ":" in topic else topic
    topics = list(dict.fromkeys(value.strip() for value in raw.split(";") if value.strip()))
    if len(topics) < 2 or quantity < 1:
        return ""
    if len(topics) > quantity:
        shift = offset % len(topics)
        topics = (topics[shift:] + topics[:shift])[:quantity]
    base, remainder = divmod(quantity, len(topics))
    allocation = "\n".join(f"- {name}: {base + (index < remainder)} questoes" for index, name in enumerate(topics))
    return "Cobertura dos topicos explicitos desta sessao:\n" + allocation + "\nRespeite esta distribuicao e identifique o topico de cada questao.\n"

