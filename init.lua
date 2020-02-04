local abr = minetest.get_mapgen_setting('active_block_range')
local abs = math.abs
local node_lava = nil

local wildlife = {}
--wildlife.spawn_rate = 0.5		-- less is more

local min=math.min
local max=math.max

local spawn_rate = 1 - max(min(minetest.settings:get('wildlife_spawn_chance') or 0.2,1),0)
local spawn_reduction = minetest.settings:get('wildlife_spawn_reduction') or 0.5

local hdrops = minetest.get_modpath("water_life")

local spawntimer = 0


local function sortout(self,ftable)
	if not ftable or #ftable < 1 then return ftable end
	local pos = mobkit.get_stand_pos(self)
	pos.y = pos.y + 0.5
	
	for i = #ftable,1,-1 do
		if water_life.find_collision(pos,ftable[i],true) then 
			table.remove(ftable,i)
		end
	end
	return ftable
end
		

function wildlife.hq_goto(self,prty,tpos)
	local func = function(self)
		if mobkit.is_queue_empty_low(self) and self.isonground then
			local pos = mobkit.get_stand_pos(self)
			if vector.distance(pos,tpos) > 1 then
				wildlife.goto_next_waypoint(self,tpos,0.5)
			else
				return true
			end
		end
	end
	mobkit.queue_high(self,func,prty)
end


function wildlife.goto_next_waypoint(self,tpos,speedfactor)
	local height, pos2 = mobkit.get_next_waypoint(self,tpos)
	if not speedfactor then speedfactor = 1 end
	
	if not height then return false end
	
	if height <= 0.01 then
		local yaw = self.object:get_yaw()
		local tyaw = minetest.dir_to_yaw(vector.direction(self.object:get_pos(),pos2))
		if abs(tyaw-yaw) > 1 then
			mobkit.lq_turn2pos(self,pos2) 
		end
		mobkit.lq_dumbwalk(self,pos2,speedfactor)
	else
		mobkit.lq_turn2pos(self,pos2) 
		mobkit.lq_dumbjump(self,height) 
	end
	return true
end


function wildlife.hq_find_food(self,prty,radius)
    
    local yaw =  self.object:get_yaw()
    local pos = mobkit.get_stand_pos(self)
    local pos1 = {x=pos.x -radius,y=pos.y-1,z=pos.z-radius}
    local pos2 = {x=pos.x +radius,y=pos.y+1,z=pos.z+radius}  --mobkit.pos_translate2d(pos,yaw,radius)
	local food = minetest.find_nodes_in_area(pos1,pos2, {"group:growing","group:plant"})
    if not food or #food < 1 then food = minetest.find_nodes_in_area(pos1,pos2, {"group:flora"}) end
	food = sortout(self,food)
	if #food < 1 then return true end
	--minetest.chat_send_all("### "..dump(#food).." ###")
	local snack = food[math.random(#food)]
    
	
    local func = function(self)
    local pos = mobkit.get_stand_pos(self)
	--water_life.temp_show(snack,10)
	
    
    if mobkit.is_queue_empty_low(self) and self.isonground then
			
			if vector.distance(pos,snack) > 1 then
				wildlife.hq_goto(self,prty+1,snack)
			else
				self.object:set_velocity({x=0,y=0,z=0})
                minetest.set_node(snack,{name="air"})
                self.hungry = self.hungry + 5
				return true
			end
		end
	end
    mobkit.queue_high(self,func,prty)
end
    

local function lava_dmg(self,dmg)
	node_lava = node_lava or minetest.registered_nodes[minetest.registered_aliases.mapgen_lava_source]
	if node_lava then
		local pos=self.object:get_pos()
		local box = self.object:get_properties().collisionbox
		local pos1={x=pos.x+box[1],y=pos.y+box[2],z=pos.z+box[3]}
		local pos2={x=pos.x+box[4],y=pos.y+box[5],z=pos.z+box[6]}
		local nodes=mobkit.get_nodes_in_area(pos1,pos2)
		if nodes[node_lava] then mobkit.hurt(self,dmg) end
	end
end

local function predator_brain(self)
	-- vitals should be checked every step
	if mobkit.timer(self,1) then lava_dmg(self,6) end
	mobkit.vitals(self)
--	if self.object:get_hp() <=100 then	
	if self.hp <= 0 then	
		mobkit.clear_queue_high(self)	-- cease all activity
        if hdrops then water_life.handle_drops(self) end
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
			local prey = mobkit.get_closest_entity(self,'aerotest:eagle')-- look for prey
			if not prey then mobkit.get_closest_entity(self,'wildlife:deer') end
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
	if self.tamed == nil then self.tamed = false end
	if mobkit.timer(self,1) then lava_dmg(self,6) end
	mobkit.vitals(self)

	if self.hp <= 0 then	
		mobkit.clear_queue_high(self)
        if hdrops then water_life.handle_drops(self) end
		mobkit.hq_die(self)
		return
	end
	
	if mobkit.timer(self,10) and self.hungry then
		if self.hungry < 10 then mobkit.hurt(self,1) end
	end
	
	if mobkit.timer(self,1) then 
		local prty = mobkit.get_queue_priority(self)
        
        if not self.hungry then self.hungry = 100 end
        if mobkit.timer(self,300) then self.hungry = self.hungry - 10 end
		
		
		if prty < 20 and self.isinliquid then
			mobkit.hq_liquid_recovery(self,20)
            self.hungry = self.hungry - 10
			return
		end
		
		local pos = self.object:get_pos() 
		
		if prty < 11  then
			local pred = mobkit.get_closest_entity(self,'wildlife:wolf')
			if pred then 
				mobkit.hq_runfrom(self,11,pred)
                self.hungry = self.hungry -5
				return
			end
		end
		if prty < 10 then
			local plyr = mobkit.get_nearby_player(self)
			if plyr and vector.distance(pos,plyr:get_pos()) < 8 and not self.tamed then 
				mobkit.hq_runfrom(self,10,plyr)
                self.hungry = self.hungry -5
				return
			end
		end
        if prty < 5 then
            if math.random(100) > self.hungry then
                wildlife.hq_find_food(self,5,5)
                return
            end
        end
		if mobkit.is_queue_empty_high(self) then
			mobkit.hq_roam(self,0)
            self.hungry = self.hungry -5
		end
	end
end

-- spawning is too specific to be included in the api, this is an example.
-- a modder will want to refer to specific names according to games/mods they're using 
-- in order for mobs not to spawn on treetops, certain biomes etc.

local function spawnstep(dtime)
    
    spawntimer = spawntimer + dtime
    if spawntimer < 10 then return end

	for _,plyr in ipairs(minetest.get_connected_players()) do
            
            spawntimer = 0
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
	
			if height and height >= 0 and height <= 100 and not liquidflag -- and math.abs(height-pos2.y) <= 30 testin
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
                        
                        if not minetest.is_protected(pos2,mobname) then
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
	max_hp = 24,
	timeout=600,
    drops = {
		{name = "default:diamond", chance = 20, min = 1, max = 3,},		
		{name = "water_life:meat_raw", chance = 2, min = 1, max = 2,},
	},
	attack={range=0.5,damage_groups={fleshy=7}},
	sounds = {
		attack='dogbite',
		warn = 'angrydog',
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
	lung_capacity = 20,			-- seconds
	max_hp = 20,
    hungry = 100,
	tamed = false,
	timeout = 600,
	attack={range=0.5,damage_groups={fleshy=3}},
	sounds = {
		scared='deer_scared',
		hurt = 'deer_hurt',
		},
    drops = {
		{name = "default:diamond", chance = 20, min = 1, max = 3,},		
		{name = "water_life:meat_raw", chance = 2, min = 1, max = 3,},
	},
	
	brainfunc = herbivore_brain,

	on_punch=function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		local hvel = vector.multiply(vector.normalize({x=dir.x,y=0,z=dir.z}),4)
		self.object:set_velocity({x=hvel.x,y=2,z=hvel.z})
		mobkit.make_sound(self,'hurt')
		mobkit.hurt(self,tool_capabilities.damage_groups.fleshy or 1)
	end,
	
	on_rightclick = function(self, clicker)
        if not clicker or not clicker:is_player() then return end
        local inv = clicker:get_inventory()
        local item = clicker:get_wielded_item()
        
        if not item or item:get_name() ~= "water_life:lasso" then return end
        if not inv:room_for_item("main", "wildlife:deer_item") then return end
        local pos = mobkit.get_stand_pos(self)
		local name = clicker:get_player_name()
		local hasowner = minetest.is_protected(pos)
        if hasowner and self.tamed then return end
                                            
        inv:add_item("main", "wildlife:deer_item")
        self.object:remove()
    end,
})



minetest.register_entity("wildlife:deer_tamed",{
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
	lung_capacity = 20,			-- seconds
	max_hp = 20,
    hungry = 100,
	tamed = true,
	timeout = 600,
	attack={range=0.5,damage_groups={fleshy=3}},
	sounds = {
		scared='deer_scared',
		hurt = 'deer_hurt',
		},
    drops = {
		{name = "water_life:meat_raw", chance = 2, min = 1, max = 3,},
	},
	
	brainfunc = herbivore_brain,

	on_punch=function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		local pos = mobkit.get_stand_pos(self)
		if minetest.is_protected(pos) then return end
                                                
		local hvel = vector.multiply(vector.normalize({x=dir.x,y=0,z=dir.z}),4)
		self.object:set_velocity({x=hvel.x,y=2,z=hvel.z})
		mobkit.make_sound(self,'hurt')
		mobkit.hurt(self,tool_capabilities.damage_groups.fleshy or 1)
	end,
                                                
	on_rightclick = function(self, clicker)
        if not clicker or not clicker:is_player() then return end
        local inv = clicker:get_inventory()
        local item = clicker:get_wielded_item()
        
        if not item or item:get_name() ~= "water_life:lasso" then return end
        if not inv:room_for_item("main", "wildlife:deer_item") then return end
        local pos = mobkit.get_stand_pos(self)
		local name = clicker:get_player_name()
		local hasowner = minetest.is_protected(pos,name)
        if  hasowner and self.tamed then return end
                                            
        inv:add_item("main", "wildlife:deer_item")
        self.object:remove()
    end,
})


minetest.register_craftitem("wildlife:deer_item", {
	description = ("a tamed Deer"),
	inventory_image = "herbivore_item.png",
    wield_scale = {x = 0.5, y = 0.5, z = 0.5},
    stack_max = 10,
    liquids_pointable = false,
    range = 10,
    on_use = minetest.item_eat(5),                                    
	groups = {food_meat = 1, flammable = 2},
    on_place = function(itemstack, placer, pointed_thing)
        if placer and not placer:is_player() then return itemstack end
        if not pointed_thing then return itemstack end
        if not pointed_thing.type == "node" then return itemstack end
        
        local pos = pointed_thing.above
        local number = water_life.count_objects(pos,nil,"wildlife:deer")
        if number.all > water_life.maxmobs or number.name > 10 then return itemstack end
                                                    
        local name = placer:get_player_name()
        if minetest.is_protected(pos,name) then return itemstack end

        local obj = minetest.add_entity(pos, "wildlife:deer_tamed")
        obj = obj:get_luaentity()
		obj.tamed = true
        itemstack:take_item()
        return itemstack
    end,
})
