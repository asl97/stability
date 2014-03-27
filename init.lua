-- stability 0.2.1 by paramat
-- For latest stable Minetest and back to 0.4.8
-- Depends default
-- License: code WTFPL

-- Parameters

local YMIN = 6000 -- Approximate realm base and atmosphere top
local YMAX = 8000
local TCEN = 7016 -- Terrain centre, average solid surface level
local WATY = 7016 -- Water surface y
local TSCA = 128 -- Terrain scale, approximate average height of hills
local STOT = 0.04 -- Stone threshold, depth of stone surface
local STABLE = 2 -- Minimum number of stacked stone nodes in column required to support sand

-- 3D noise for terrain

local np_terrain = {
	offset = 0,
	scale = 1,
	spread = {x=256, y=192, z=256},
	seed = 5900033,
	octaves = 5,
	persist = 0.67
}

-- Stuff

stability = {}

-- Nodes

minetest.register_node("stability:stone", {
	description = "STB Stone",
	tiles = {"default_stone.png"},
	is_ground_content = false,
	groups = {cracky=3},
	drop = "default:stone",
	sounds = default.node_sound_stone_defaults(),
})

-- On generated function

minetest.register_on_generated(function(minp, maxp, seed)
	if minp.y < YMIN or maxp.y > YMAX then
		return
	end

	local t1 = os.clock()
	local x1 = maxp.x
	local y1 = maxp.y
	local z1 = maxp.z
	local x0 = minp.x
	local y0 = minp.y
	local z0 = minp.z
	
	print ("[stability] chunk minp ("..x0.." "..y0.." "..z0..")")
	
	local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
	local area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
	local data = vm:get_data()
	
	local c_air = minetest.get_content_id("air")
	local c_sand = minetest.get_content_id("default:sand")
	local c_water = minetest.get_content_id("default:water_source")
	
	local c_stbstone = minetest.get_content_id("stability:stone")
	
	local sidelen = x1 - x0 + 1
	local chulens = {x=sidelen, y=sidelen, z=sidelen}
	local minpos = {x=x0, y=y0, z=z0}
	
	local nvals_terrain = minetest.get_perlin_map(np_terrain, chulens):get3dMap_flat(minpos)
	
	local ni = 1
	local stable = {} -- 80 entry table, each entry is a count of consecutive stone nodes in that vertical column
	for z = z0, z1 do -- for each xy plane progressing northwards
		for x = x0, x1 do -- set initial values of stability table by scanning top x row of chunk below
			local si = x - x0 + 1 -- stability table index
			local nodename = minetest.get_node({x=x,y=y0-1,z=z}).name
			if nodename == "air"
			or nodename == "default:water_source" then
				stable[si] = 0
			else -- solid nodes, but also "ignore" in ungenerated chunks, this assumption looks better than
				stable[si] = STABLE -- assuming ignore is unstable, and creates some fun sand to collapse
			end
		end
		
		for y = y0, y1 do
			local vi = area:index(x0, y, z)
			for x = x0, x1 do
				local si = x - x0 + 1
				local grad = (TCEN - y) / TSCA
				local density = nvals_terrain[ni] + grad
				if density >= STOT then
					data[vi] = c_stbstone -- only stone can reset an unstable column to stable
					stable[si] = stable[si] + 1 -- increment count of consecutive stone nodes in column
				elseif density >= 0 and density < STOT and stable[si] >= STABLE then
					data[vi] = c_sand -- only add if enough supporting stone nodes below
				elseif y <= WATY then
					data[vi] = c_water
					stable[si] = 0 -- set to unstable
				else
					data[vi] = c_air
					stable[si] = 0 -- set to unstable
				end
				ni = ni + 1
				vi = vi + 1
			end
		end
	end
	
	vm:set_data(data)
	vm:set_lighting({day=0, night=0})
	vm:calc_lighting()
	vm:write_to_map(data)
	local chugent = math.ceil((os.clock() - t1) * 1000)
	print ("[stability] "..chugent.." ms")
end)