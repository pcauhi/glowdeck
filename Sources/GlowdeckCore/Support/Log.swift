import os

/// `log stream --predicate 'subsystem == "app.glowdeck"'` to watch.
public let log = Logger(subsystem: "app.glowdeck", category: "core")
