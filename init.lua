local abr = minetest.get_mapgen_setting('active_block_range')

local wildlife = {}
--wildlife.spawn_rate = 0.5		-- less is more

local min=math.min
local max=math.max

local spawn_rate = 1 - max(min(minetest.settings:get('wildlife_spawn_chance') or 0.2,1),0)
local spawn_reduction = minetest.settings:get('wildlife_spawn_reduction') or 0.5

local function node_dps_dmg(self)
	local pos = self.object:get_pos()
	local box = self.object:get_properties().collisionbox
	local pos1 = {x = pos.x + box[1], y = pos.y + box[2], z = pos.z + box[3]}
	local pos2 = {x = pos.x + box[4], y = pos.y + box[5], z = pos.z + box[6]}
	local nodes_overlap = mobkit.get_nodes_in_area(pos1, pos2)
	local total_damage = 0

	for node_def, _ in pairs(nodes_overlap) do
		local dps = node_def.damage_per_second
		if dps then
			total_damage = math.max(total_damage, dps)
		end
	end

	if total_damage ~= 0 then
		mobkit.hurt(self, total_damage)
	end
end

local function predator_brain(self)
	-- vitals should be checked every step
	if mobkit.timer(self,1) then node_dps_dmg(self) end
	mobkit.vitals(self)
--	if self.object:get_hp() <=100 then	
	if self.hp <= 0 then	
		mobkit.clear_queue_high(self)									-- cease all activity
		mobkit.hq_die(self)												-- kick the bucket
		return
	end
	
	if mobkit.timer(self,1) then 			-- decision making needn't happen every engine step
		local prty = mobkit.get_queue_priority(self)
		
		if prty < 20 and self.isinliquid then
			mobkit.hq_liquid_recovery(self,20)
			return
		end
		
		local pos=self.object:get_pos()
		
		-- hunt
		if prty < 10 then							-- if not busy with anything important
			local prey = mobkit.get_closest_entity(self,'wildlife:deer')	-- look for prey
			if prey then 
				mobkit.hq_hunt(self,10,prey) 									-- and chase it
			end
		end
		
		if prty < 9 then
			local plyr = mobkit.get_nearby_player(self)					
			if plyr and vector.distance(pos,plyr:get_pos()) < 10 then	-- if player close
				mobkit.hq_warn(self,9,plyr)								-- try to repel them
			end															-- hq_warn will trigger subsequent bhaviors if needed
		end
		
		-- fool around
		if mobkit.is_queue_empty_high(self) then
			mobkit.hq_roam(self,0)
		end
	end
end

local function herbivore_brain(self)
	if mobkit.timer(self,1) then node_dps_dmg(self) end
	mobkit.vitals(self)

	if self.hp <= 0 then	
		mobkit.clear_queue_high(self)
		mobkit.hq_die(self)
		return
	end
	
	if mobkit.timer(self,1) then 
		local prty = mobkit.get_queue_priority(self)
		
		if prty < 20 and self.isinliquid then
			mobkit.hq_liquid_recovery(self,20)
			return
		end
		
		local pos = self.object:get_pos() 
		
		if prty < 11  then
			local pred = mobkit.get_closest_entity(self,'wildlife:wolf')
			if pred then 
				mobkit.hq_runfrom(self,11,pred) 
				return
			end
		end
		if prty < 10 then
			local plyr = mobkit.get_nearby_player(self)
			if plyr and vector.distance(pos,plyr:get_pos()) < 8 then 
				mobkit.hq_runfrom(self,10,plyr)
				return
			end
		end
		if mobkit.is_queue_empty_high(self) then
			mobkit.hq_roam(self,0)
		end
	end
end

-- spawning is too specific to be included in the api, this is an example.
-- a modder will want to refer to specific names according to games/mods they're using 
-- in order for mobs not to spawn on treetops, certain biomes etc.

local function spawnstep(dtime)

	for _,plyr in ipairs(minetest.get_connected_players()) do
		if math.random()<dtime*0.2 then	-- each player gets a spawn chance every 5s on average
			local vel = plyr:get_player_velocity()
			local spd = vector.length(vel)
			local chance = spawn_rate * 1/(spd*0.75+1)  -- chance is quadrupled for speed=4

			local yaw
			if spd > 1 then
				-- spawn in the front arc
				yaw = plyr:get_look_horizontal() + math.random()*0.35 - 0.75
			else
				-- random yaw
				yaw = math.random()*math.pi*2 - math.pi
			end
			local pos = plyr:get_pos()
			local dir = vector.multiply(minetest.yaw_to_dir(yaw),abr*16)
			local pos2 = vector.add(pos,dir)
			pos2.y=pos2.y-5
			local height, liquidflag = mobkit.get_terrain_height(pos2,32)
	
			if height and height >= 0 and not liquidflag -- and math.abs(height-pos2.y) <= 30 testin
			and mobkit.nodeatpos({x=pos2.x,y=height-0.01,z=pos2.z}).is_ground_content then

				local objs = minetest.get_objects_inside_radius(pos,abr*16+5)
				local wcnt=0
				local dcnt=0
				for _,obj in ipairs(objs) do				-- count mobs in abrange
					if not obj:is_player() then
						local luaent = obj:get_luaentity()
						if luaent and luaent.name:find('wildlife:') then
							chance=chance + (1-chance)*spawn_reduction	-- chance reduced for every mob in range
							if luaent.name == 'wildlife:wolf' then wcnt=wcnt+1
							elseif luaent.name=='wildlife:deer' then dcnt=dcnt+1 end
						end
					end
				end
--minetest.chat_send_all('chance '.. chance)
				if chance < math.random() then

					-- if no wolves and at least one deer spawn wolf, else deer
--					local mobname = (wcnt==0 and dcnt > 0) and 'wildlife:wolf' or 'wildlife:deer'
					local mobname = dcnt>wcnt+1 and 'wildlife:wolf' or 'wildlife:deer'

					pos2.y = height+0.5
					objs = minetest.get_objects_inside_radius(pos2,abr*16-2)
					for _,obj in ipairs(objs) do				-- do not spawn if another player around
						if obj:is_player() then return end
					end
--minetest.chat_send_all('spawnin '.. mobname ..' #deer:' .. dcnt)
					minetest.add_entity(pos2,mobname)			-- ok spawn it already damnit
				end
			end
		end
	end
end


minetest.register_globalstep(spawnstep)

minetest.register_entity("wildlife:wolf",{
											-- common props
	physical = true,
	stepheight = 0.1,				--EVIL!
	collide_with_objects = true,
	collisionbox = {-0.3, -0.01, -0.3, 0.3, 0.7, 0.3},
	visual = "mesh",
	mesh = "wolf.b3d",
	textures = {"kit_wolf.png"},
	visual_size = {x = 1.3, y = 1.3},
	static_save = true,
	makes_footstep_sound = true,
	on_step = mobkit.stepfunc,	-- required
	on_activate = mobkit.actfunc,		-- required
	get_staticdata = mobkit.statfunc,
											-- api props
	springiness=0,
	buoyancy = 0.75,					-- portion of hitbox submerged
	max_speed = 5,
	jump_height = 1.26,
	view_range = 24,
	lung_capacity = 10, 		-- seconds
	max_hp = 14,
	timeout=600,
	attack={range=0.5,damage_groups={fleshy=7}},
	sounds = {
		attack='dogbite',
		warn = 'angrydog',
		},
	animation = {
	walk={range={x=10,y=29},speed=30,loop=true},
	stand={range={x=1,y=5},speed=1,loop=true},
	},

	brainfunc = predator_brain,
	
	on_punch=function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		if mobkit.is_alive(self) then
			local hvel = vector.multiply(vector.normalize({x=dir.x,y=0,z=dir.z}),4)
			self.object:set_velocity({x=hvel.x,y=2,z=hvel.z})
			
			mobkit.hurt(self,tool_capabilities.damage_groups.fleshy or 1)

			if type(puncher)=='userdata' and puncher:is_player() then	-- if hit by a player
				mobkit.clear_queue_high(self)							-- abandon whatever they've been doing
				mobkit.hq_hunt(self,10,puncher)							-- get revenge
			end
		end
	end

})

minetest.register_entity("wildlife:deer",{
											-- common props
	physical = true,
	stepheight = 0.1,				--EVIL!
	collide_with_objects = true,
	collisionbox = {-0.35, -0.19, -0.35, 0.35, 0.65, 0.35},
	visual = "mesh",
	mesh = "herbivore.b3d",
	textures = {"herbivore.png"},
	visual_size = {x = 1.3, y = 1.3},
	static_save = true,
	makes_footstep_sound = true,
	on_step = mobkit.stepfunc,	-- required
	on_activate = mobkit.actfunc,		-- required
	get_staticdata = mobkit.statfunc,
											-- api props
	springiness=0,
	buoyancy = 0.9,
	max_speed = 5,
	jump_height = 1.26,
	view_range = 24,
	lung_capacity = 10,			-- seconds
	max_hp = 10,
	timeout = 600,
	attack={range=0.5,damage_groups={fleshy=3}},
	sounds = {
		scared='deer_scared',
		hurt = 'deer_hurt',
		},
	animation = {
	walk={range={x=10,y=29},speed=30,loop=true},
	stand={range={x=1,y=5},speed=1,loop=true},
	},

	brainfunc = herbivore_brain,

	on_punch=function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		local hvel = vector.multiply(vector.normalize({x=dir.x,y=0,z=dir.z}),4)
		self.object:set_velocity({x=hvel.x,y=2,z=hvel.z})
		mobkit.make_sound(self,'hurt')
		mobkit.hurt(self,tool_capabilities.damage_groups.fleshy or 1)
	end,
})


-- minetest.register_on_chat_message(
	-- function(name, message)
		-- if message == 'doit' then
			-- local plyr=minetest.get_player_by_name(name)
			-- local pos=mobkit.get_stand_pos(plyr)
			-- local nodes = mobkit.get_nodes_in_area(pos,mobkit.pos_shift(pos,{x=-1,z=-1,y=-1}))
			-- for p,n in pairs(nodes) do
				-- minetest.chat_send_all(p.name ..' '.. dump(n))
			-- end
		-- end
	-- end
-- )
