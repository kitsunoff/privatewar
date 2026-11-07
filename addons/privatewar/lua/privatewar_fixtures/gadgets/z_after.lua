-- Test fixture (T-1.1): loads after the broken files and records whether it saw a previous file's fields.
GADGET.SawPrevious = GADGET.Name ~= nil
GADGET.Name = "After"
GADGET.Cost = 3
