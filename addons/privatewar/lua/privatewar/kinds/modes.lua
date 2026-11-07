-- The modes kind (02-modes.md d.7; 01-extensibility.md d.16). One file or folder per mode in lua/privatewar/modes/
-- with a MODE table. Never auto-subscribed (d.18): the active mode is dispatched through PW.ActiveMode, last.
KIND.Folder = "modes"
KIND.Global = "MODE"
KIND.Subscribe = "never"
KIND.Required = { Name = "string", Teams = "number" }
