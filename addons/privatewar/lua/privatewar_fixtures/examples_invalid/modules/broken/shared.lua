-- Invalid example (T-1.18): modules have no required fields, so the closest real rejection is a module whose file
-- fails while loading. The module is skipped with one log line carrying the error text (01-extensibility.md d.15).

MODULE.Name = "Broken"
error("example: this module fails while loading")
