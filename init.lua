-- stability 0.1.1 by paramat
-- For latest stable Minetest and back to 0.4.8
-- Depends default
-- License: code WTFPL

-- Parameters

local YMIN = 6000
local YMAX = 8000
local TCEN = 7000
local WATY = 7000 -- approximate water y, is rounded down to near base of chunk
local GRAD = 128
local STOT = 0.04

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

waty = (80 * math.floor((WATY + 32) / 80)) - 32 + 12

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
	local c_stone = minetest.get_content_id("default:stone")
	local c_sand = minetest.get_content_id("default:sand")
	local c_water = minetest.get_content_id("default:water_source")
	
	local sidelen = x1 - x0 + 1
	local chulens = {x=sidelen, y=sidelen, z=sidelen}
	local minpos = {x=x0, y=y0, z=z0}
	
	local nvals_terrain = minetest.get_perlin_map(np_terrain, chulens):get3dMap_flat(minpos)
	
	local ni = 1
	local stable = {} -- stability table, a true/false entry for the top node in each vertical column of xy plane
	for z = z0, z1 do -- for each xy plane progressing northwards
		for x = x0, x1 do -- set initial values of stability table by scanning top x row of chunk below
			local si = x - x0 + 1 -- stability table index starts from 1 not 0
			local nodename = minetest.get_node({x=x,y=y0-1,z=z}).name
			if nodename == "air"
			or nodename == "default:water_source" then
				stable[si] = false
			else -- solid nodes
				stable[si] = true -- assume "ignore" in ungenerated chunks is solid
			end
		end
		
		for y = y0, y1 do -- for each x row progressing upwards
			local vi = area:index(x0, y, z) -- get voxel index for first node in x row
			for x = x0, x1 do -- for each node do
				local si = x - x0 + 1
				local grad = (TCEN - y) / GRAD
				local density = nvals_terrain[ni] + grad
				if density >= STOT then
					data[vi] = c_stone
					stable[si] = true -- only stone can reset an unstable column to stable
				elseif density >= 0 and density < STOT and stable[si] then -- only add if node is stable
					data[vi] = c_sand
				elseif y <= waty then
					data[vi] = c_water
					stable[si] = false -- set to unstable
				else
					data[vi] = c_air
					stable[si] = false -- set to unstable
				end
				ni = ni + 1 -- increment perlinmap noise index
				vi = vi + 1 -- increment voxel index along x row
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