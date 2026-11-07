-- Gate fixture: must be rejected by glualint (unused variable, double negation). Never loaded by the game.
local unused = 1
if not (1 == 2) then
    print("x")
end
