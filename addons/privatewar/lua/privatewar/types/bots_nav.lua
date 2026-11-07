---@meta
-- Types of the bots_nav module (T-5.5; 07-bots.md d.6). Code: lua/privatewar/modules/bots_nav/ (shared.lua: the pure
-- search, cache, cost layers and the service; init.lua: the CNavArea adapter and the engine hooks).

---The graph the search runs on. A node is any value usable as a table key (the engine adapter uses the area id).
---@class PW.NavGraph
---@field Neighbours fun(node: any): any[] nodes reachable in one step
---@field Cost fun(from: any, to: any): number cost of the step, >= 0
---@field Heuristic fun(node: any, goal: any): number estimate of the remaining cost, never above the real cost
---@field Nodes? fun(): any[] every node; needed only for baking cost layers
---@field Position? fun(node: any): Vector where the node is; used to fill PW.NavHandle.positions

---Options of PW.BotNav.NewSearch.
---@class PW.NavSearchOpts
---@field iterationCap? integer node expansions after which the search gives up with a partial path, default 4000

---@alias PW.NavStatus "queued"|"running"|"found"|"partial"|"unreachable"|"cancelled"

---One A* search that runs in slices (resumable). status: running until it ends as found, partial or unreachable.
---@class PW.NavSearch
---@field status "running"|"found"|"partial"|"unreachable"
---@field path any[]? nodes from start to goal (found) or to the best node so far (partial)
---@field iterations integer node expansions done
---@field best any the expanded node closest to the goal by the heuristic
---@field Step fun(maxIterations: integer): "running"|"found"|"partial"|"unreachable" runs up to N expansions

---Unreachable-pair cache: a pair that A* proved unreachable is remembered until it expires.
---@class PW.NavUnreachableCache
---@field Mark fun(from: any, to: any)
---@field Has fun(from: any, to: any): boolean false once the entry has expired
---@field Clear fun()
---@field Count fun(): integer entries not yet expired

---Result handle of a path request. Poll status, or pass a callback to RequestPath.
---@class PW.NavHandle
---@field status PW.NavStatus
---@field path any[]? nodes (area ids) from start to goal; for status partial: to the node closest to the goal
---@field positions Vector[]? the path as positions, when the graph has Position
---@field partial boolean true when the iteration cap ended the search before the goal was reached
---@field cached boolean true when the answer came from the unreachable cache without a search
---@field iterations integer node expansions the search needed
---@field slices integer scheduler jobs the search used
---@field done boolean true once status is found, partial, unreachable or cancelled
---@field from any the requested start node
---@field to any the requested goal node

---A cost layer: the extra cost of entering a node (in distance units, >= 0; a negative result counts as 0).
---@alias PW.NavCostLayer fun(node: any, graph: PW.NavGraph): number

---Options of PW.BotNav.NewService.
---@class PW.NavServiceOpts
---@field graph PW.NavGraph
---@field scheduler? { Enqueue: fun(job: fun()) } default PW.BotScheduler
---@field clock? fun(): number seconds, default CurTime-independent SysTime
---@field sliceIterations? integer expansions per scheduler job, default 150
---@field sliceMs? number a slice also ends after this many ms, default 1
---@field iterationCap? integer expansions before a partial path, default 4000
---@field unreachableTtl? number seconds a proven unreachable pair stays cached, default 30
---@field bakeInterval? number seconds between two bakes of the cost layers, default 1
---@field bakeChunk? integer nodes baked per Tick, default 256

---@class PW.NavCounters
---@field requests integer
---@field found integer
---@field partial integer
---@field unreachable integer
---@field cacheHits integer
---@field cancelled integer
---@field slices integer
---@field iterations integer
---@field bakes integer completed bakes of the cost layers
---@field layerErrors integer cost layers that raised an error

---A path service over one graph: requests, cancel, cache, cost layers.
---@class PW.NavService
---@field RequestPath fun(from: any, to: any, callback?: fun(handle: PW.NavHandle)): PW.NavHandle
---@field Cancel fun(handle: PW.NavHandle)
---Registers or replaces a cost layer; it applies from the next bake.
---@field RegisterCostLayer fun(id: string, layer: PW.NavCostLayer)
---@field UnregisterCostLayer fun(id: string): boolean
---Bakes every layer into the per-node cost table at once (Tick does it in chunks, about once a second).
---@field Bake fun()
---@field Tick fun() advances the baking; call it every server tick
---@field GetCostTable fun(): table<any, number> the baked per-node extra cost (the blackboard `danger` table)
---@field ClearUnreachable fun()
---@field GetCounters fun(): PW.NavCounters

---Death danger: recent deaths make the areas around them costly; the cost decays linearly.
---@class PW.NavDangerOpts
---@field clock? fun(): number seconds
---@field radius? number units, default 600
---@field weight? number extra cost at the centre of a fresh death, default 800
---@field decay? number seconds until a death is forgotten, default 120
---@field maxDeaths? integer deaths kept, default 64

---@class PW.NavDanger
---@field Record fun(pos: Vector)
---@field Layer PW.NavCostLayer the cost layer; the node must have a position in the graph
---@field Count fun(): integer deaths still remembered

---@class PW.BotNavLib
---@field SliceIterations integer
---@field SliceMs number
---@field IterationCap integer
---@field NewSearch fun(graph: PW.NavGraph, start: any, goal: any, opts?: PW.NavSearchOpts): PW.NavSearch
---@field NewUnreachableCache fun(ttl: number, clock?: fun(): number): PW.NavUnreachableCache
---@field NewService fun(opts: PW.NavServiceOpts): PW.NavService
---@field NewDanger fun(opts?: PW.NavDangerOpts): PW.NavDanger
---Server: the CNavArea adapter over a list of areas; nodes are the area ids.
---@field AreaGraph? fun(areas: CNavArea[]): PW.NavGraph
---Server: the default service over PW.Map.GetNavAreas(), rebuilt when the area list changes; nil without a navmesh.
---@field Service? fun(): PW.NavService?
---Server: path between two positions (projected on the navmesh); nil when there is no navmesh or no area near them.
---@field RequestPath? fun(from: Vector, to: Vector, callback?: fun(handle: PW.NavHandle)): PW.NavHandle?
---@field Cancel? fun(handle: PW.NavHandle)
---@field RegisterCostLayer? fun(id: string, layer: PW.NavCostLayer)
---@field UnregisterCostLayer? fun(id: string): boolean
---Server: the death danger layer of the default service.
---@field Danger? PW.NavDanger

---@class PW
---@field BotNav PW.BotNavLib
