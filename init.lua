-- Parameters

local YWATER = 1 -- y of water level
local YSURF = 4 -- y of surface centre and top of beach
local TERSCA = 128 -- Terrain vertical scale in nodes
local TSTONE = 0.04 -- Stone density threshold, depth of sand or biome nodes
local DEBUG = false

-- 3D noise

local np_terrain = {
	offset = 0,
	scale = 1,
	spread = {x = 384, y = 192, z = 384},
	seed = 5900033,
	octaves = 5,
	persist = 0.63,
	lacunarity = 2.0,
	--flags = ""
}

-- 2D noise

local np_biome = {
	offset = 0,
	scale = 1,
	spread = {x = 512, y = 512, z = 512},
	seed = -188900,
	octaves = 3,
	persist = 0.4,
	lacunarity = 2.0,
	--flags = ""
}


-- Nodes

minetest.register_node("stability:grass", {
	description = "Grass",
	tiles = {"default_grass.png", "default_dirt.png", "default_grass.png"},
	groups = {crumbly = 3},
	sounds = default.node_sound_dirt_defaults({
		footstep = {name = "default_grass_footstep", gain = 0.25},
	}),
})

minetest.register_node("stability:dirt", {
	description = "Dirt",
	tiles = {"default_dirt.png"},
	groups = {crumbly = 3},
	sounds = default.node_sound_dirt_defaults(),
})


-- Set mapgen parameters

minetest.set_mapgen_params({mgname = "singlenode",
		flags = "nolight", water_level = YWATER})


-- Constants

local c_air       = minetest.CONTENT_AIR
local c_ignore    = minetest.CONTENT_IGNORE

local c_stone     = minetest.get_content_id("default:stone")
local c_destone   = minetest.get_content_id("default:desert_stone")
local c_sand      = minetest.get_content_id("default:sand")
local c_desand    = minetest.get_content_id("default:desert_sand")
local c_dirtsnow  = minetest.get_content_id("default:dirt_with_snow")
local c_water     = minetest.get_content_id("default:water_source")
	
local c_grass     = minetest.get_content_id("stability:grass")
local c_dirt      = minetest.get_content_id("stability:dirt")


-- Initialize noise objects to nil

local nobj_terrain = nil
local nobj_biome   = nil


-- Localise noise buffers

local nbuf_terrain = {}
local nbuf_biome = {}

-- Localise data buffer

local dbuf = {}

-- On generated function

minetest.register_on_generated(function(minp, maxp, seed)
	local t0 = os.clock()

	local x1 = maxp.x
	local y1 = maxp.y
	local z1 = maxp.z
	local x0 = minp.x
	local y0 = minp.y
	local z0 = minp.z
	
	local sidelen = x1 - x0 + 1
	local ystridevm = sidelen + 32 -- strides for voxelmanip
	local zstridevm = ystridevm ^ 2
	local ystridepm = sidelen + 2 -- strides for perlinmaps, densitymap, stability map
	local zstridepm = ystridepm ^ 2

	local chulens3d = {x = sidelen + 2, y = sidelen + 2, z = sidelen + 2}
	local chulens2d = {x = sidelen + 2, y = sidelen + 2, z = 1}
	local minpos3d = {x = x0 - 1, y = y0 - 1, z = z0 - 1}
	local minpos2d = {x = x0 - 1, y = z0 - 1}
	
	nobj_terrain = nobj_terrain or minetest.get_perlin_map(np_terrain, chulens3d)
	nobj_biome = nobj_biome or minetest.get_perlin_map(np_biome, chulens2d)
	
	local nvals_terrain = nobj_terrain:get3dMap_flat(minpos3d, nbuf_terrain)
	local nvals_biome = nobj_biome:get2dMap_flat(minpos2d, nbuf_biome)

	local dvals = {} -- 3D densitymap

	local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
	local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
	local data = vm:get_data(dbuf)

	-- Place stone
	local ni3d = 1
	local ni2d = 1
	for z = z0 - 1, z1 + 1 do
		for y = y0 - 1, y1 + 1 do
			local vi = area:index(x0 - 1, y, z)
			for x = x0 - 1, x1 + 1 do
				local n_terrain = nvals_terrain[ni3d]
				local n_biome = nvals_biome[ni2d]

				local grad = (YSURF - y) / TERSCA
				local tstone = TSTONE
				if y < YSURF then -- make shore and seabed shallower
					grad = grad * 4
					tstone = TSTONE * 4
				end
				local density = n_terrain + grad
				dvals[ni3d] = density

				if density >= tstone then
					if n_biome > 0.4 then
						data[vi] = c_destone
					else
						data[vi] = c_stone
					end
				elseif y == y1 + 1 and x >= x0 and x <= x1 and z >= z0 and z <= z1 then
					data[vi] = c_air
				end

				ni3d = ni3d + 1
				ni2d = ni2d + 1
				vi = vi + 1
			end
			ni2d = ni2d - ystridepm
		end
		ni2d = ni2d + ystridepm
	end
	
	-- Place sub-surface biome nodes
	local stable = {} -- stability map
	for y = y0, y1 + 1 do
		local tstone = TSTONE
		if y < YSURF then
			tstone = TSTONE * 4
		end
		for z = z0, z1 do
			local vi = area:index(x0, y, z)
			local di = (z - z0 + 1) * zstridepm + -- densitymap index
					(y - y0 + 1) * ystridepm + 2 -- +2 because starting at x = x0
			local ni2d = (z - z0 + 1) * ystridepm + 2 -- biome noise and stability maps

			for x = x0, x1 do
				local density = dvals[di]
				local n_biome = nvals_biome[ni2d]

				if density >= tstone then -- existing stone
					stable[ni2d] = true
				elseif density >= 0 and (stable[ni2d] or y == y0) then -- biome layer
					local nodu  = data[(vi - ystridevm)]
					local node  = data[(vi - ystridevm + 1)]
					local nodw  = data[(vi - ystridevm - 1)]
					local nodn  = data[(vi - ystridevm + zstridevm)]
					local nods  = data[(vi - ystridevm - zstridevm)]
					local nodne = data[(vi - ystridevm + zstridevm + 1)]
					local nodnw = data[(vi - ystridevm + zstridevm - 1)]
					local nodse = data[(vi - ystridevm - zstridevm + 1)]
					local nodsw = data[(vi - ystridevm - zstridevm - 1)]

					if y == y0 then -- also check for ignore
						if nodu == c_air or nodu == c_ignore
								or node == c_air or node == c_ignore
								or nodw == c_air or nodw == c_ignore
								or nodn == c_air or nodn == c_ignore
								or nods == c_air or nods == c_ignore
								or nodne == c_air or nodne == c_ignore
								or nodnw == c_air or nodnw == c_ignore
								or nodse == c_air or nodse == c_ignore
								or nodsw == c_air or nodsw == c_ignore then
							stable[ni2d] = false
						else
							stable[ni2d] = true
						end
					else
						if node == c_air
								or nodw == c_air
								or nodn == c_air
								or nods == c_air
								or nodne == c_air
								or nodnw == c_air
								or nodse == c_air
								or nodsw == c_air then
							stable[ni2d] = false
						end
					end

					if stable[ni2d] then
						if y <= YSURF then
							data[vi] = c_sand
						elseif n_biome > 0.4 then
							data[vi] = c_desand
						elseif n_biome < -0.4 then
							data[vi] = c_dirt
						else
							data[vi] = c_dirt
						end
					end
				else
					stable[ni2d] = false
				end

				vi = vi + 1
				di = di + 1
				ni2d = ni2d + 1
			end
		end
	end

	if y1 > YSURF then
		-- Place surface biome nodes
		for z = z0, z1 do
			local ni2d = (z - z0 + 1) * ystridepm + 2
			for x = x0, x1 do
				local aircount = 0
				local n_biome = nvals_biome[ni2d]
				local vi = area:index(x, y1 + 2, z)
				for y = y1 + 2, y0, -1 do
					if y <= YSURF then
						break
					end

					local nodid = data[vi]
					if nodid == c_air then
						aircount = aircount + 1
					elseif aircount >= 1 then -- surface found
						if nodid == c_dirt then
							if n_biome < -0.4 then
								data[vi] = c_dirtsnow
							else
								data[vi] = c_grass
							end
						end
						aircount = 0
					end
					vi = vi - ystridevm
				end
				ni2d = ni2d + 1
			end
		end
	end

	if y0 <= YWATER then
		-- Place water
		for z = z0, z1 do
			for y = y0, y1 do
				local vi = area:index(x0, y, z)
				for x = x0, x1 do
					if data[vi] == c_air and y <= YWATER then
						data[vi] = c_water
					end
					vi = vi + 1
				end
			end
		end
	end
	
	vm:set_data(data)
	vm:calc_lighting({x = x0, y = y0 - 1, z = z0}, {x = x1, y = y1 + 1, z = z1})
	vm:write_to_map(data)
	vm:update_liquids()

	if DEBUG then
		local chugent = math.ceil((os.clock() - t0) * 1000)
		print ("[stability] "..chugent.." ms")
	end
end)
