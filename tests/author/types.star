def literal(text):
    return binding("literal", value("string", text))

def choice(enabled):
    if enabled:
        return value("bool", True)
    return value("bool", False)
