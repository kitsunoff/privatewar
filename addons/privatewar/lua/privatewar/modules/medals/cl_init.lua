-- Medals, client (T-4.11). Keeps the last medal the server announced; the popups (T-6.4) read PW.Medals.Last.

local lib = PW.Medals --[[@as PW.MedalsLib]]

net.Receive("pw_medal", function()
    lib.Last = { id = net.ReadString(), at = CurTime() }
end)
