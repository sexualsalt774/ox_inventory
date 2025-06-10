local Inventory = require 'modules.inventory.server' -- Load ox inventory

-- Setup inventory for a player when they load in
local function setupPlayer(src)
    local source = src
    local player = Fetch:Source(source)
    local char = player:GetData("Character")
    local sid = char:GetData("SID")
    local inventory = MySQL.query.await('SELECT id, count(id) as Count, name as Owner, item_id as Name, dropped as Temp, MAX(quality) as Quality, information as MetaData, slot as Slot, MIN(creationDate) AS CreateDate FROM inventory WHERE NAME = ? GROUP BY slot ORDER BY slot ASC', { string.format("%s-%s", sid, 1)}) or {}

    server.setPlayerInventory({
        source = source,
        inventory = inventory,
        identifier = sid,
        name = ('%s %s'):format(char:GetData("First"), char:GetData("Last")),
    })

    Inventory.SetItem(source, 'money', char:GetData("Cash"))
end

RegisterServerEvent('Inventory:Cash', function(key)
    Middleware:TriggerEvent('Inventory:Wallet', source)
end)


AddEventHandler("Inventory:Shared:DependencyUpdate", RetrieveComponents)
function RetrieveComponents()
	Fetch = exports["mythic-base"]:FetchComponent("Fetch")
	Utils = exports["mythic-base"]:FetchComponent("Utils")
	Middleware = exports["mythic-base"]:FetchComponent("Middleware")
    Wallet = exports["mythic-base"]:FetchComponent("Wallet")
end

AddEventHandler("Core:Shared:Ready", function()
	exports["mythic-base"]:RequestDependencies("Inventory", {
        "Fetch",
        "Utils",
        "Middleware",
        "Wallet",
	}, function(error)
		if #error > 0 then
			return
		end
		RetrieveComponents()

		Middleware:Add("Characters:Spawning", function(source)
			setupPlayer(source)
		end, 1)

        Middleware:Add("Inventory:Wallet", function(source)
            local player = Fetch:Source(source)
            local char = player:GetData("Character")
            Inventory.SetItem(source, 'money', char:GetData("Cash"))
		end, 1)
	end)
end)

function server.setPlayerData(player)
    -- TODO MYTHIC:
end

function server.syncInventory(inv)
    -- TODO MYTHIC:
end

function server.UseItem(source, itemName, data)
    -- TODO MYTHIC:
end

function server.hasLicense(inv, license)
    -- TODO MYTHIC:
end

function server.buyLicense(inv, license)
    -- TODO MYTHIC:
end

function server.isPlayerBoss(playerId, group, grade)
    -- TODO MYTHIC:
end

-- TODO Convert all component functions to use ox inventory (its currently using mythic inventories default code as a placeholder)
_CRAFTING = {
	RegisterBench = function(self, id, label, targeting, location, restrictions, recipes, canUseSchematics)
		while not itemsLoaded do
			Wait(10)
		end

		_cooldowns[id] = _cooldowns[id] or {}
		_types[id] = {
			id = id,
			label = label,
			targeting = targeting,
			location = location,
			restrictions = restrictions,
			recipes = {},
			canUseSchematics = canUseSchematics or false,
		}

		for k, v in pairs(recipes) do
			if itemsDatabase[v.result.name] ~= nil then
				v.id = k
				Crafting:AddRecipeToBench(id, k, v)
			end
		end

		if _knownRecipes[id] ~= nil then
			for k, v in pairs(_knownRecipes[id]) do
				if itemsDatabase[v.result.name] ~= nil then
					v.id = k
					Crafting:AddRecipeToBench(id, k, v)
				end
			end
		end
	end,
	AddRecipeToBench = function(self, bench, id, recipe)
		if _types[bench] == nil then
			return
		end
		recipe.id = id
		_types[bench].recipes[id] = recipe
	end,
	Craft = {
		Start = function(self, crafter, bench, result, qty)
			if _inProg[crafter] ~= nil or _types[bench] == nil or _types[bench].recipes[result] == nil then
				return { error = true, message = "Already Crafting" }
			end

			local reagents = {}
			for k, v in ipairs(_types[bench].recipes[result].items) do
				if reagents[v.name] ~= nil then
					reagents[v.name] = reagents[v.name] + (v.count * qty)
				else
					reagents[v.name] = v.count * qty
				end
			end

			local makingItem = _types[bench].recipes[result].result
			local reqSlotPerItem = itemsDatabase[makingItem.name].isStackable or 1
			local totalRequiredSlots = math.ceil((makingItem.count * qty) / reqSlotPerItem)
			local freeSlots = Inventory:GetFreeSlotNumbers(crafter, 1)
			if #freeSlots < totalRequiredSlots then
				return { error = true, message = "Inventory Full" }
			end

			for k, v in pairs(reagents) do
				if not Inventory.Items:Has(crafter, 1, k, v) then
					return { error = true, message = "Missing Ingredients" }
				end
			end

			if _cooldowns[bench][result] ~= nil and _cooldowns[bench][result] > (os.time() * 1000) then
				return { error = true, message = "Recipe On Cooldown" }
			end

			_inProg[crafter] = {
				bench = bench,
				result = result,
				qty = tonumber(qty),
			}

			local t = deepcopy(_types[bench].recipes[result])
			t.time = t.time * qty

			return {
				error = false,
				data = t,
				string = _types[bench].targeting?.actionString or "Crafting",
			}
		end,
		End = function(self, crafter)
			if _inProg[crafter] == nil or _types[_inProg[crafter].bench] == nil then
				return false
			end

			local recipe = _types[_inProg[crafter].bench].recipes[_inProg[crafter].result]

			local reagents = {}
			for k, v in ipairs(recipe.items) do
				if reagents[v.name] ~= nil then
					reagents[v.name] = reagents[v.name] + (v.count * _inProg[crafter].qty)
				else
					reagents[v.name] = v.count * _inProg[crafter].qty
				end
			end

			local reqSlotPerItem = itemsDatabase[recipe.result.name].isStackable or 1
			local totalRequiredSlots = math.ceil((recipe.result.count * _inProg[crafter].qty) / reqSlotPerItem)
			local freeSlots = Inventory:GetFreeSlotNumbers(crafter, 1)
			if #freeSlots < totalRequiredSlots then
				return false
			end

			for k, v in pairs(reagents) do
				if not Inventory.Items:Remove(crafter, 1, k, v, true) then
					return false
				end
			end

			local p = promise.new()

			local meta = {}
			if itemsDatabase[recipe.result.name].type == 2 and not itemsDatabase[recipe.result.name].noSerial then
				meta.Scratched = true
			end

			if recipe.cooldown then
				InsertCooldown(_inProg[crafter].bench, recipe.id, (os.time() * 1000) + recipe.cooldown)
			end

			if Inventory:AddItem(crafter, recipe.result.name, recipe.result.count * _inProg[crafter].qty, meta, 1) then
				p:resolve(_inProg[crafter].bench)
			else
				p:resolve(nil)
			end
			_inProg[crafter] = nil
			return Citizen.Await(p)
		end,
		Cancel = function(self, crafter)
			if _inProg[crafter] == nil then
				return false
			end
			_inProg[crafter] = nil
			return true
		end,
	},
	Schematics = {
		Has = function(self, bench, item)
			if _types[bench] ~= nil then
				for k, v in ipairs(_types[bench].recipes) do
					if v.schematic == item then
						return true
					end
				end
			end

			return false
		end,
		Add = function(self, bench, item)
			if _types[bench] ~= nil and _schematics[item] ~= nil then
				if not Crafting.Schematics:Has(bench, item) then
					Database.Game:insertOne({
						collection = "schematics",
						document = {
							bench = bench,
							item = item,
						},
					})

					local f = table.copy(_schematics[item])
					f.schematic = item
					Crafting:AddRecipeToBench(bench, item, f)
				end
			end

			return false
		end,
	},
}
INVENTORY = {
	CreateDropzone = function(self, routeId, coords)
		local area = {
			id = string.format("%s:%s", math.ceil(coords.x), math.ceil(coords.y)),
			route = routeId,
			coords = {
				x = coords.x,
				y = coords.y,
				z = coords.z,
			},
		}

		table.insert(_dropzones, area)
		TriggerClientEvent("Inventory:Client:AddDropzone", -1, area)

		return area.id
	end,
	CheckDropZones = function(self, routeId, coords)
		local found = nil

		for k, v in ipairs(_dropzones) do
			if v.route == routeId then
				local dz = v.coords
				local distance = #(vector3(coords.x, coords.y, coords.z) - vector3(dz.x, dz.y, dz.z))
				if distance < 2.0 and (found == nil or distance < found.distance) then
					found = {
						id = v.id,
						position = v.coords,
						distance = distance,
						route = v.route,
					}
				end
			end
		end

		return found
	end,
	RemoveDropzone = function(self, routeId, id)
		for k, v in ipairs(_dropzones) do
			if v.id == id and v.route == routeId then
				if not _doingThings[string.format("%s-%s", id, 10)] then
					table.remove(_dropzones, k)
					TriggerClientEvent("Inventory:Client:RemoveDropzone", -1, id)
				end
				break
			end
		end
	end,
	DropExists = function(self, routeId, id)
		for k, v in ipairs(_dropzones) do
			if v.id == id and v.route == routeId then
				return true
			end
		end

		return false
	end,
	GetInventory = function(self, source, owner, invType)
		return getInventory(source, owner, invType)
	end,
	GetSecondaryData = function(self, _src, invType, Owner, vehClass, vehModel, isRaid, nameOverride, slotOverride, capacityOverride)
		if _src and invType and Owner then
			if entityPermCheck(_src, invType) or (isRaid and Player(_src).state.onDuty == "police") then
				if not _openInvs[string.format("%s-%s", Owner, invType)] or _openInvs[string.format("%s-%s", Owner, invType)] == _src then
					if not LoadedEntitys[invType].shop then
						_openInvs[string.format("%s-%s", Owner, invType)] = _src
					end
					
					local name = nameOverride or (LoadedEntitys[invType].name or "Unknown")
					if LoadedEntitys[tonumber(invType)].shop and shopLocations[Owner] ~= nil then
						name = string.format(
							"%s (%s)",
							shopLocations[Owner].name,
							LoadedEntitys[tonumber(invType)].name
						)
					end

					local requestedInventory = {
						size = getSlotCount(invType, vehClass, vehModel, slotOverride),
						name = name,
						class = vehClass,
						model = vehModel,
						capacity = getCapacity(invType, vehClass, vehModel, capacityOverride),
						shop = LoadedEntitys[tonumber(invType)].shop or false,
						free = LoadedEntitys[tonumber(invType)].free or false,
						inventory = {},
						invType = invType,
						owner = Owner,
						loaded = false,
						slotOverride = slotOverride,
						capacityOverride = capacityOverride,
					}

					return requestedInventory
				else
					return nil
				end
			end
		end
	end,
	GetSecondary = function(self, _src, invType, Owner, vehClass, vehModel, isRaid, nameOverride, slotOverride, capacityOverride)
		if _src and invType and Owner then
			if entityPermCheck(_src, invType) or (isRaid and Player(_src).state.onDuty == "police") then
				if not _openInvs[string.format("%s-%s", Owner, invType)] or _openInvs[string.format("%s-%s", Owner, invType)] == _src then
					if not LoadedEntitys[invType].shop then
						_openInvs[string.format("%s-%s", Owner, invType)] = _src
					end

					local name = nameOverride or (LoadedEntitys[invType].name or "Unknown")
					if LoadedEntitys[tonumber(invType)].shop and shopLocations[Owner] ~= nil then
						name = string.format(
							"%s (%s)",
							shopLocations[Owner].name,
							LoadedEntitys[tonumber(invType)].name
						)
					end
	
					local requestedInventory = {
						size = getSlotCount(invType, vehClass, vehModel, slotOverride),
						name = name,
						class = vehClass,
						model = vehModel,
						capacity = getCapacity(invType, vehClass, vehModel, capacityOverride),
						shop = LoadedEntitys[tonumber(invType)].shop or false,
						free = LoadedEntitys[tonumber(invType)].free or false,
						action = LoadedEntitys[tonumber(invType)].action or false,
						inventory = getInventory(_src, Owner, invType),
						invType = invType,
						owner = Owner,
						loaded = true,
						slotOverride = slotOverride,
						capacityOverride = capacityOverride,
					}
					
					return requestedInventory
				else
					return nil
				end
			else
				return nil
			end
		else
			return nil
		end
	end,
	OpenSecondary = function(self, _src, invType, Owner, vehClass, vehModel, isRaid, nameOverride, slotOverride, capacityOverride)
		if _src and invType and Owner then
			local player = Fetch:Source(_src)
			local char = player:GetData("Character")

			local plyrInvData = {
				size = (LoadedEntitys[1].slots or 10),
				name = char:GetData("First") .. " " .. char:GetData("Last"),
				inventory = {},
				invType = 1,
				capacity = LoadedEntitys[1].capacity,
				owner = char:GetData("SID"),
				isWeaponEligble = Weapons:IsEligible(_src),
				qualifications = char:GetData("Qualifications") or {},
			}
		
			TriggerEvent("Inventory:Server:Opened", _src, Owner, invType)

			TriggerClientEvent("Inventory:Client:Open", _src, plyrInvData, Inventory:GetSecondaryData(_src, invType, Owner, vehClass, vehModel, isRaid, nameOverride, slotOverride, capacityOverride))
		
			plyrInvData.inventory = getInventory(_src, char:GetData("SID"), 1)
			plyrInvData.loaded = true
		
			TriggerClientEvent("Inventory:Client:Cache", _src, plyrInvData)
			TriggerClientEvent("Inventory:Client:Load", _src, plyrInvData, Inventory:GetSecondary(_src, invType, Owner, vehClass, vehModel, isRaid, nameOverride, slotOverride, capacityOverride))
		end
	end,
	GetSlots = function(self, Owner, Type)
		local db = MySQL.query.await('SELECT slot as Slot FROM inventory WHERE name = ? GROUP BY slot ORDER BY slot', {
			string.format("%s-%s", Owner, Type)
		})

		local slots = {}
		for k, v in ipairs(db) do
			table.insert(slots, v.Slot)
		end
		return slots
	end,
	HasItems = function(self, Owner, Type)
		return MySQL.single.await('SELECT COUNT(id) as count FROM inventory WHERE name = ?', {
			string.format("%s-%s", Owner, Type)
		}).count > 0
	end,
	GetMatchingSlot = function(self, Owner, Name, Count, Type)
		if not itemsDatabase[Name].isStackable then
			return nil
		end

		return (MySQL.single.await('SELECT slot as Slot FROM inventory WHERE name = ? AND item_id = ? GROUP BY slot HAVING COUNT(item_id) <= ?', {
			string.format("%s-%s", Owner, Type),
			Name,
			itemsDatabase[Name].isStackable - Count
		}))?.Slot
	end,
	GetFreeSlotNumbers = function(self, Owner, invType, vehClass, vehModel)
		local result = Inventory:GetSlots(Owner, invType)
		local occupiedTable = {}
		local unOccupiedSlots = {}
		for k, v in ipairs(result) do
			occupiedTable[v] = true
		end

		local total = 8
		if LoadedEntitys[invType] ~= nil then
			total = getSlotCount(invType, vehClass or false, vehModel or false)
		else
			Logger:Error("Inventory", string.format("Entity Type ^2%s^7 Was Attempted To Be Loaded", invType))
		end

		for i = 1, total do
			if not occupiedTable[i] then
				table.insert(unOccupiedSlots, i)
			end
		end

		table.sort(unOccupiedSlots)

		return unOccupiedSlots
	end,
	GetSlot = function(self, Owner, Slot, Type)
		local item = MySQL.single.await('SELECT id, count(Name) as Count, name as Owner, item_id as Name, dropped as Temp, MAX(quality) as Quality, information as MetaData, slot as Slot, MIN(creationDate) as CreateDate FROM inventory WHERE name = ? AND slot = ? GROUP BY slot ORDER BY slot ASC', {
			string.format("%s-%s", Owner, Type),
			Slot
		})

		if item ~= nil then
			item.MetaData = json.decode(item.MetaData or "{}")
			item.Owner = Owner
			item.invType = Type
		end

		return item
	end,
	GetProvidedSlots = function(self, Owner, Type, Slots)
		return MySQL.single.await('SELECT id, count(Name) as Count, name as Owner, item_id as Name, dropped as Temp, MAX(quality) as Quality, information as MetaData, slot as Slot, MIN(creationDate) as CreateDate FROM inventory WHERE name = ? AND slot IN (?) GROUP BY slot ORDER BY slot ASC', {
			string.format("%s-%s", Owner, Type),
			Slots
		})
	end,
	GetItem = function(self, id)
		return MySQL.single.await('SELECT id, count(Name) as Count, name as Owner, item_id as Name, dropped as Temp, quality as Quality, information as MetaData, slot as Slot, creationDate as CreateDate FROM inventory WHERE id = ?', {
			id
		})
	end,
	CreateItemWithNoMeta = function(self, Owner, Name, Count, Slot, MetaData, invType, isRecurse)
		if not Count or not tonumber(Count) or Count <= 0 then
			Count = 1
		end

		local itemExist = itemsDatabase[Name]
		if itemExist then
			local p = promise.new()

			if
				not itemExist.isStackable and Count > 1
				or Count > 50
				or (type(itemExist.isStackable) == "number" and Count > itemExist.isStackable and itemExist.isStackable > 0)
			then
				while
					not itemExist.isStackable and itemExist.isStackable ~= -1 and Count > 1
					or Count > 50
					or (type(itemExist.isStackable) == "number" and Count > itemExist.isStackable and itemExist.isStackable > 0)
				do
					local s = Count > 50 and 50 or itemExist.isStackable or 1
					self:CreateItemWithNoMeta(Owner, Name, Count, Slot, MetaData, invType, true)
					Count = Count - s
				end
			end

			return Inventory:AddSlot(Owner, Name, Count, MetaData, Slot, invType)
		else
			return false
		end
	end,
	CreateItem = function(self, Owner, Name, Count, Slot, md, invType, isRecurse, forceCreateDate, quality)
		local MetaData = table.copy(md or {})

		if not Count or not tonumber(Count) or Count <= 0 then
			Count = 1
		end

		local itemExist = itemsDatabase[Name]
		if itemExist then
			local p = promise.new()

			if
				not itemExist.isStackable and Count > 1
				or Count > 10000
				or (type(itemExist.isStackable) == "number" and Count > itemExist.isStackable and itemExist.isStackable > 0)
			then
				while
					not itemExist.isStackable and itemExist.isStackable ~= -1 and Count > 1
					or Count > 10000
					or (type(itemExist.isStackable) == "number" and Count > itemExist.isStackable and itemExist.isStackable > 0)
				do
					local s = Count > 10000 and 10000 or itemExist.isStackable or 1
					self:CreateItem(Owner, Name, Count, Slot, MetaData, invType, true, quality)
					Count = Count - s
				end
			end

			if itemExist.type == 2 then
				if not MetaData.SerialNumber and not itemExist.noSerial then
					if MetaData.Scratched then
						MetaData.ScratchedSerialNumber = Weapons:Purchase(Owner, itemExist, true, MetaData.Company)
						MetaData.Scratched = nil
					else
						MetaData.SerialNumber = Weapons:Purchase(Owner, itemExist, false, MetaData.Company)
					end
					MetaData.Company = nil
				end
			elseif itemExist.type == 10 and not MetaData.Container then
				MetaData.Container = string.format("container:%s", Sequence:Get("Container"))
			elseif itemExist.type == 11 and not MetaData.Quality then
				MetaData.Quality = math.random(100)
			elseif itemExist.name == "govid" and invType == 1 then
				local plyr = Fetch:SID(Owner)
				local char = plyr:GetData("Character")
				local genStr = "Male"
				if char:GetData("Gender") == 1 then
					genStr = "Female"
				end
				MetaData.Name = string.format("%s %s", char:GetData("First"), char:GetData("Last"))
				MetaData.Gender = genStr
				MetaData.PassportID = plyr:GetData("AccountID")
				MetaData.StateID = char:GetData("SID")
				MetaData.DOB = char:GetData("DOB")
			elseif itemExist.name == "moneybag" and not MetaData.Finish then
				MetaData.Finished = os.time() + (60 * 60 * 24 * math.random(1, 3))
			elseif itemExist.name == "crypto_voucher" and not MetaData.CryptoCoin and not MetaData.Quantity then
				MetaData.CryptoCoin = "PLEB"
				MetaData.Quantity = math.random(25, 50)
			elseif itemExist.name == "vpn" then
				MetaData.VpnName = {
					First = Generator.Name:First(),
					Last = Generator.Name:Last(),
				}
			elseif itemExist.name == "WEAPON_PETROLCAN" then
				MetaData.ammo = 4500
			elseif itemExist.name == "cigarette_pack" then
				MetaData.Count = 30
			elseif itemExist.name == "choplist" and not MetaData.ChopList then
				MetaData.ChopList = Phone.LSUnderground.Chopping:GenerateList(math.random(4, 8), math.random(3, 5))
			elseif itemExist.name == "meth_table" and not MetaData.MethTable then
				MetaData.MethTable = Drugs.Meth:GenerateTable(1)
			elseif itemExist.name == "adv_meth_table" and not MetaData.MethTable then
				MetaData.MethTable = Drugs.Meth:GenerateTable(2)
			elseif itemExist.name == "meth_bag" or itemExist.name == "meth_brick" or itemExist.name == "coke_bag" or itemExist.name == "coke_brick" then
				if not quality then
					quality = math.random(1, 100)
				end
				if itemExist.name == "meth_brick" then
					MetaData.Finished = os.time() + (60 * 60 * 24)
				end
			elseif itemExist.name == "paleto_access_codes" and not MetaData.AccessCodes then
				MetaData.AccessCodes = {
					Robbery:GetAccessCodes('paleto')[1]
				}
			end

			return Inventory:AddSlot(Owner, Name, Count, MetaData, Slot, invType, forceCreateDate or false, quality or false)
		else
			return false
		end
	end,
	AddItem = function(self, Owner, Name, Count, md, invType, vehClass, vehModel, entity, isRecurse, Slot, forceCreateDate, quality)
		local MetaData = table.copy(md or {})

		if vehClass == nil then
			vehClass = false
		end

		if vehModel == nil then
			vehModel = false
		end

		if entity == nil then
			entity = false
		end

		if not Count or not tonumber(Count) or Count <= 0 then
			Count = 1
		end

		if invType == 1 then
			if not isRecurse then
				local plyr = Fetch:SID(Owner)
				TriggerClientEvent("Inventory:Client:Changed", plyr:GetData("Source"), "add", Name, Count)
			end
		end

		local itemExist = itemsDatabase[Name]
		if itemExist then
			local invWeight = Inventory.Items:GetWeights(Owner, invType)
			local totWeight = invWeight + (Count * itemExist.weight)

			if
				not itemExist.isStackable and Count > 1
				or Count > 10000
				or (type(itemExist.isStackable) == "number" and Count > itemExist.isStackable and itemExist.isStackable > 0)
			then
				while
					not itemExist.isStackable and Count > 1
					or Count > 10000
					or (type(itemExist.isStackable) == "number" and Count > itemExist.isStackable and itemExist.isStackable > 0)
				do
					local s = Count > 10000 and 10000 or itemExist.isStackable or 1
					self:AddItem(Owner, Name, s, MetaData, invType, vehClass, vehModel or false, entity or false, true, Slot or false, forceCreateDate or false, quality or false)
					Count = Count - s
				end
			end

			local slots = Inventory:GetFreeSlotNumbers(Owner, invType, vehClass, vehModel)
			if
				(totWeight > getCapacity(invType, vehClass, vehmodel) and itemExist.weight > 0)
				or (#slots == 0 or slots[1] > getSlotCount(invType, vehClass or false, vehModel or false))
			then
				local plyr = Fetch:SID(Owner)
				local coords = { x = 900.441, y = -1757.186, z = 21.359 }
				local route = 0

				if plyr ~= nil then
					local x, y, z = table.unpack(GetEntityCoords(GetPlayerPed(plyr:GetData("Source"))))
					coords = { x = x, y = y, z = z - 0.98 }
					route = Player(plyr:GetData("Source")).state.currentRoute
				elseif entity ~= nil then
					local x, y, z = table.unpack(GetEntityCoords(entity))
					coords = { x = x, y = y, z = z }
					route = GetEntityRoutingBucket(entity)
				end

				invType = 10
				local dz = Inventory:CheckDropZones(route, coords)
				if dz == nil then
					Owner = Inventory:CreateDropzone(route, coords)
				else
					Owner = dz.id
				end

				slots = Inventory:GetFreeSlotNumbers(Owner, invType, vehClass, vehModel)
			end

			if itemExist.staticMetadata ~= nil then
				for k, v in pairs(itemExist.staticMetadata) do
					if MetaData[k] == nil then
						MetaData[k] = v
					end
				end
			end

			if itemExist.type == 2 then
				if not MetaData.SerialNumber and not itemExist.noSerial then
					if MetaData.Scratched then
						MetaData.ScratchedSerialNumber = Weapons:Purchase(Owner, itemExist, true, MetaData.Company)
						MetaData.Scratched = nil
					else
						MetaData.SerialNumber = Weapons:Purchase(Owner, itemExist, false, MetaData.Company)
					end
					MetaData.Company = nil
				end
			elseif itemExist.type == 10 and not MetaData.Container then
				MetaData.Container = string.format("container:%s", Sequence:Get("Container"))
			elseif itemExist.type == 11 and not MetaData.Quality then
				MetaData.Quality = math.random(100)
			elseif itemExist.name == "govid" and invType == 1 then
				local plyr = Fetch:SID(Owner)
				local char = plyr:GetData("Character")
				local genStr = "Male"
				if char:GetData("Gender") == 1 then
					genStr = "Female"
				end
				MetaData.Name = string.format("%s %s", char:GetData("First"), char:GetData("Last"))
				MetaData.Gender = genStr
				MetaData.PassportID = plyr:GetData("AccountID")
				MetaData.StateID = char:GetData("SID")
				MetaData.DOB = char:GetData("DOB")
			elseif itemExist.name == "moneybag" and not MetaData.Finish then
				MetaData.Finished = os.time() + (60 * 60 * 24 * math.random(1, 3))
			elseif itemExist.name == "crypto_voucher" and not MetaData.CryptoCoin and not MetaData.Quantity then
				MetaData.CryptoCoin = "PLEB"
				MetaData.Quantity = math.random(25, 50)
			elseif itemExist.name == "vpn" then
				MetaData.VpnName = {
					First = Generator.Name:First(),
					Last = Generator.Name:Last(),
				}
			elseif itemExist.name == "WEAPON_PETROLCAN" then
				MetaData.ammo = 4500
			elseif itemExist.name == "cigarette_pack" then
				MetaData.Count = 30
			elseif itemExist.name == "choplist" and not MetaData.ChopList then
				MetaData.ChopList = Phone.LSUnderground.Chopping:GenerateList(math.random(4, 8), math.random(3, 5))
			elseif itemExist.name == "meth_table" and not MetaData.MethTable then
				MetaData.MethTable = Drugs.Meth:GenerateTable(1)
			elseif itemExist.name == "adv_meth_table" and not MetaData.MethTable then
				MetaData.MethTable = Drugs.Meth:GenerateTable(2)
			elseif itemExist.name == "meth_bag" or itemExist.name == "meth_brick" or itemExist.name == "coke_bag" or itemExist.name == "coke_brick" then
				if not quality then
					quality = math.random(1, 100)
				end
				if itemExist.name == "meth_brick" then
					MetaData.Finished = os.time() + (60 * 60 * 24)
				end
			elseif itemExist.name == "paleto_access_codes" and not MetaData.AccessCodes then
				MetaData.AccessCodes = {
					Robbery:GetAccessCodes('paleto')[1]
				}
			end

			local retval = nil

			if not itemExist.isStackable then
				retval = Inventory:AddSlot(Owner, Name, 1, MetaData, slots[1], invType, forceCreateDate or false, quality or false)
			else
				local mSlot = Inventory:GetMatchingSlot(Owner, Name, Count, invType)
				if mSlot == nil then
					retval = Inventory:AddSlot(Owner, Name, Count, MetaData, slots[1], invType, forceCreateDate or false, quality or false)
				else
					retval = Inventory:AddSlot(Owner, Name, Count, MetaData, mSlot, invType, forceCreateDate or false, quality or false)
				end
			end

			if invType == 1 then
				if WEAPON_PROPS[Name] ~= nil then
					_refreshAttchs[Owner] = true
				end
				refreshShit(Owner, true)
			end

			return retval
		else
			return false
		end
	end,
	AddSlot = function(self, Owner, Name, Count, MetaData, Slot, Type, forceCreateDate, quality)
		if Count <= 0 then
			Logger:Error("Inventory", "[AddSlot] Cannot Add " .. Count .. " of an Item (" .. Owner .. ":" .. Type .. ")")
			return false
		end

		if Slot == nil then
			local freeSlots = Inventory:GetFreeSlotNumbers(Owner, Type)
			if #freeSlots == 0 then
				Logger:Error("Inventory", "[AddSlot] No Available Slots For " .. Owner .. ":" .. Type .. " And Passed Slot Was Nil")
				return false
			end
			Slot = freeSlots[1]
		end

		if itemsDatabase[Name] == nil then
			Logger:Error(
				"Inventory",
				string.format("Slot %s in %s-%s has invalid item %s", Slot, Owner, Type, Name)
			)
			return false
		end

		local qry = 'INSERT INTO inventory (name, item_id, slot, quality, information, creationDate, expiryDate, dropped) VALUES '
		local params = {}

		local created = forceCreateDate or os.time()
		local expiry = -1
		if itemsDatabase[Name].durability ~= nil and itemsDatabase[Name].isDestroyed then
			expiry = created + itemsDatabase[Name].durability
		end

		for i = 1, Count do
			table.insert(params, string.format("%s-%s", Owner, Type))
			table.insert(params, Name)
			table.insert(params, Slot)
			table.insert(params, quality or 0)
			table.insert(params, json.encode(MetaData))
			table.insert(params, created)
			table.insert(params, expiry)
			table.insert(params, Type == 10 and 1 or 0)
			qry = qry .. '(?, ?, ?, ?, ?, ?, ?, ?)'
			if i < Count then
				qry = qry .. ','
			end
		end

		qry = qry .. ';'

		local ids = MySQL.insert.await(qry, params)

		return { id = ids, metadata = MetaData}
	end,
	SetItemCreateDate = function(self, id, value)
		MySQL.query.await('UPDATE inventory SET creationDate = ? WHERE id = ?', {
			value,
			id,
		})
	end,
	SetMetaDataKey = function(self, id, key, value)
		local slot = Inventory:GetItem(id)
		if slot ~= nil then
			local md = json.decode(slot.MetaData or "{}")
			md[key] = value
			MySQL.query.await('UPDATE inventory SET information = ? WHERE id = ?', {
				json.encode(md),
				id,
			})
			return md
		else
			return {}
		end
	end,
	UpdateMetaData = function(self, id, updatingMeta)
		if type(updatingMeta) ~= "table" then
			return false
		end
		
		local slot = Inventory:GetItem(id)
		if slot ~= nil then
			local md = json.decode(slot.MetaData or "{}")

			for k, v in pairs(updatingMeta) do
				md[k] = v
			end

			MySQL.query.await('UPDATE inventory SET information = ? WHERE id = ?', {
				json.encode(md),
				id,
			})

			return md
		else
			return {}
		end
	end,
	Items = {
		GetData = function(self, item)
			return itemsDatabase[item]
		end,
		GetCount = function(self, owner, invType, item)
			local counts = Inventory.Items:GetCounts(owner, invType)
			return counts[item] or 0
		end,
		GetCounts = function(self, owner, invType)
			local counts = {}

			local qry = MySQL.query.await('SELECT COUNT(id) as Count, item_id as Name FROM inventory WHERE name = ? GROUP BY item_id', {
				string.format("%s-%s", owner, invType)
			})

			for k, v in ipairs(qry) do
				counts[v.Name] = v.Count
			end

			return counts
		end,
		GetWeights = function(self, owner, invType)
			local items = MySQL.query.await('SELECT id, count(id) as Count, item_id as Name FROM inventory WHERE NAME = ? GROUP BY item_id', {
				string.format('%s-%s', owner, invType)
			})

			local weights = 0
			for k, slot in ipairs(items) do
				weights += (slot.Count * itemsDatabase[slot.Name].weight or 0)
			end

			return weights
		end,
		GetFirst = function(self, Owner, Name, invType)
			local item = MySQL.single.await("SELECT id, name as Owner, item_id as Name, dropped as Temp, quality as Quality, information as MetaData, slot as Slot, creationDate as CreateDate FROM inventory WHERE NAME = ? AND item_id = ? ORDER BY quality DESC, creationDate ASC LIMIT 1", {
				string.format("%s-%s", Owner, invType),
				Name,
			})

			if item ~= nil then
				item.MetaData = json.decode(item.MetaData or "{}")
				item.Owner = Owner
				item.invType = invType
			end
			
			return item
		end,
		GetAll = function(self, Owner, Name, invType)
			local items = MySQL.query.await("SELECT id, name as Owner, item_id as Name, dropped as Temp, quality as Quality, information as MetaData, slot as Slot, creationDate as CreateDate FROM inventory WHERE NAME = ? AND item_id = ? ORDER BY quality DESC, creationDate ASC", {
				string.format("%s-%s", Owner, invType),
				Name,
			})

			if #items > 0 then
				for k, v in ipairs(items) do
					items[k].MetaData = json.decode(items[k].MetaData or "{}")
					local t = split(items[k].Owner, '-')
					items[k].Owner = tonumber(t[1]) or t[1]
					items[k].invType = tonumber(t[2])
				end
			end

			return items
		end,
		Has = function(self, owner, invType, item, count)
			return (MySQL.single.await('SELECT id, count(id) as Count FROM inventory WHERE name = ? AND item_id = ? GROUP BY item_id', {
				string.format("%s-%s", owner, invType),
				item
			})?.Count or 0) >= (count or 1)
		end,
		HasId = function(self, owner, invType, id)
			return MySQL.single.await('SELECT id, count(Name) as Count FROM inventory WHERE id = ? AND name = ?', {
				id,
				string.format("%s-%s", owner, invType),
			}) ~= nil
		end,
		HasItems = function(self, source, items)
			local player = Fetch:Source(source)
			local char = player:GetData("Character")
			local charId = char:GetData("SID")
			for k, v in ipairs(items) do
				if not Inventory.Items:Has(charId, 1, v.item, v.count) then
					return false
				end
			end
			return true
		end,
		HasAnyItems = function(self, source, items)
			local player = exports["mythic-base"]:FetchComponent("Fetch"):Source(source)
			local char = player:GetData("Character")
			local charId = char:GetData("SID")

			for k, v in ipairs(items) do
				if Inventory.Items:Has(charId, 1, v.item, v.count) then
					return true
				end
			end

			return false
		end,
		GetAllOfType = function(self, owner, invType, itemType)
			local f = {}
			local params = {}

			for k, v in pairs(itemsDatabase) do
				if v.type == itemType then
					table.insert(f, string.format('"%s"', v.name))
				end
			end

			local qry = string.format(
				'SELECT id, count(id) as Count, name as Owner, item_id as Name, dropped as Temp, quality as Quality, information as MetaData, slot as Slot, creationDate as CreateDate FROM inventory WHERE name = ? AND item_id IN (%s) GROUP BY item_id ORDER BY creationDate ASC',
				table.concat(f, ',')
			)
			return MySQL.query.await(qry, { string.format("%s-%s", owner, invType) })
		end,
		GetAllOfTypeNoStack = function(self, owner, invType, itemType)
			local f = {}
			local params = {}

			for k, v in pairs(itemsDatabase) do
				if v.type == itemType then
					table.insert(f, string.format('"%s"', v.name))
				end
			end

			local qry = string.format(
				'SELECT id, name as Owner, item_id as Name, dropped as Temp, quality as Quality, information as MetaData, slot as Slot, creationDate as CreateDate FROM inventory WHERE name = ? AND item_id IN (%s)',
				table.concat(f, ',')
			)
			return MySQL.query.await(qry, { string.format("%s-%s", owner, invType) })
		end,
		RegisterUse = function(self, item, id, cb)
			if ItemCallbacks[item] == nil then
				ItemCallbacks[item] = {}
			end
			ItemCallbacks[item][id] = cb
		end,
		Use = function(self, source, item, cb)
			if item == nil then
				return cb(false)
			end

			if not itemsDatabase[item.Name]?.isUsable or _inUse[source] then
				return cb(false)
			end

			local itemData = itemsDatabase[item.Name]
			if
				not itemData.durability
				or item ~= nil
					and item.CreateDate ~= nil
					and item.CreateDate + itemData.durability > os.time()
			then
				if itemData.closeUi then
					TriggerClientEvent("Inventory:CloseUI", source)
				end

				if
					itemData.useRestrict == nil
					or (itemData.useRestrict.job ~= nil and Jobs.Permissions:HasJob(
						source,
						itemData.useRestrict.job.id,
						itemData.useRestrict.job.workplace or false,
						itemData.useRestrict.job.grade or false,
						false,
						false,
						itemData.useRestrict.job.permissionKey or false
					) and (not itemData.useRestrict.job.duty or Player(source).state.onDuty == itemData.useRestrict.job.id))
					or (itemData.useRestrict.state and hasValue(char:GetData("States"), itemData.useRestrict.state))
					or (itemData.useRestrict.rep ~= nil and Reputation:GetLevel(source, itemData.useRestrict.rep.id) >= itemData.useRestrict.rep.level)
					or (itemData.useRestrict.character ~= nil and itemData.useRestrict.character == char:GetData("ID"))
					or (itemData.useRestrict.admin and plyr.Permissions:IsAdmin())
				then
					_inUse[source] = true
					TriggerClientEvent("Inventory:Client:InUse", source, _inUse[source])
					TriggerClientEvent("Inventory:Client:Changed", source, itemData.type == 2 and "holster" or "used", item.Name, 0, item.Slot)

					local used = true
					if itemData.animConfig ~= nil then
						used = false
						local p = promise.new()
						Callbacks:ClientCallback(source, "Inventory:ItemUse", itemData.animConfig, function(state)
							p:resolve(state)
						end)
						used = Citizen.Await(p)
					end

					if used then
						local retard = false
						if ItemCallbacks[item.Name] ~= nil then
							for k, callback in pairs(ItemCallbacks[item.Name]) do
								retard = true
								callback(source, item, itemsDatabase[item.Name])
							end
						elseif itemData.imitate and ItemCallbacks[itemData.imitate] ~= nil then
							for k, callback in pairs(ItemCallbacks[itemData.imitate]) do
								retard = true
								callback(source, item, itemsDatabase[item.Name])
							end
						end

						if retard then
							TriggerClientEvent("Markers:ItemAction", source, item)
						end
					end

					local char = Fetch:Source(source):GetData("Character")
					sendRefreshForClient(source, char:GetData("SID"), 1, item.Slot)
					_inUse[source] = false
					TriggerClientEvent("Inventory:Client:InUse", source, _inUse[source])
					cb(used)
				else
					Execute:Client(source, "Notification", "Error", "You Can't Use That")
					cb(false)
				end

			else
				cb(false)
			end
		end,
		Remove = function(self, owner, invType, item, count, skipUpdate)
			local results = MySQL.query.await("DELETE FROM inventory WHERE name = ? AND item_id = ? ORDER BY slot ASC, creationDate ASC LIMIT ?", {
				string.format("%s-%s", owner, invType),
				item,
				count,
			})

			if not skipUpdate then
				if invType == 1 then
					local plyr = Fetch:SID(owner)
					if plyr ~= nil then
						local source = plyr:GetData("Source")
						local char = plyr:GetData("Character")
						TriggerClientEvent("Inventory:Client:Changed", source, "removed", item, count)
						if WEAPON_PROPS[item] ~= nil then
							_refreshAttchs[owner] = source
						end
						refreshShit(owner)
					end
				end
			end

			return results.affectedRows >= count
		end,
		RemoveId = function(self, owner, invType, item)
			MySQL.query.await("DELETE FROM inventory WHERE id = ?", { item.id })

			if invType == 1 then
				local plyr = Fetch:SID(tonumber(owner))
				if plyr ~= nil then
					local source = plyr:GetData("Source")
					TriggerClientEvent("Inventory:Client:Changed", source, "removed", item.Name, 1)
					if WEAPON_PROPS[item.Name] ~= nil then
						_refreshAttchs[owner] = source
					end
					refreshShit(owner)
				end
			end

			return true
		end,
		RemoveAll = function(self, owner, type, item)
			if type == 1 then
				local plyr = Fetch:SID(owner)
				if plyr ~= nil then
					local count = MySQL.scalar.await('SELECT COUNT(item_id) as count FROM inventory WHERE name = ? and item_id = ?', {
						string.format("%s-%s", owner, type),
						item,
					})

					if count > 0 then
						TriggerClientEvent("Inventory:Client:Changed", plyr:GetData("Source"), "removed", item, count)
					end
				end
			end

			MySQL.query.await('DELETE FROM inventory WHERE name = ? AND item_id = ?', {
				string.format("%s-%s", owner, type),
				item,
			})
			return true
		end,
		RemoveSlot = function(self, Owner, Name, Count, Slot, invType)
			local slot = Inventory:GetSlot(Owner, Slot, invType)
			if slot == nil then
				Logger:Error(
					"Inventory",
					"Failed to remove " .. Count .. " from Slot " .. Slot .. " for " .. Owner,
					{ console = false }
				)
				return false
			else
				if slot.Count >= Count then
					MySQL.query.await('DELETE FROM inventory WHERE name = ? AND slot = "?" AND item_id = ? ORDER BY creationDate ASC LIMIT ?', {
						string.format("%s-%s", Owner, invType),
						Slot,
						Name,
						Count,
					})
	
					if invType == 1 then
						local plyr = Fetch:SID(Owner)
						if plyr ~= nil then
							local source = plyr:GetData("Source")
							local char = plyr:GetData("Character")
							TriggerClientEvent("Inventory:Client:Changed", source, "removed", Name, Count)
							if WEAPON_PROPS[item] ~= nil then
								_refreshAttchs[Owner] = source
							end
							refreshShit(Owner)
						end
					end
	
					return true
				else
					return false
				end
			end
		end,
		RemoveList = function(self, owner, invType, items)
			for k, v in ipairs(items) do
				Inventory.Items:Remove(owner, invType, v.name, v.count)
			end
		end,
		GetWithStaticMetadata = function(self, masterKey, mainIdName, textureIdName, gender, data)
			for k, v in pairs(itemsDatabase) do
				if v.staticMetadata ~= nil
					and v.staticMetadata[masterKey] ~= nil
					and v.staticMetadata[masterKey][gender] ~= nil
					and v.staticMetadata[masterKey][gender][mainIdName] == data[mainIdName]
					and v.staticMetadata[masterKey][gender][textureIdName] == data[textureIdName]
				then
					return k
				end
			end

			return nil
		end,
	},
	Holding = {
		Put = function(self, source)
			CreateThread(function()
				local p = promise.new()
				local plyr = Fetch:Source(source)
				if plyr ~= nil then
					local char = plyr:GetData("Character")
					if char ~= nil then
						local inv = getInventory(source, char:GetData("SID"), 1)

						if #inv > 0 then
							local freeSlots = Inventory:GetFreeSlotNumbers(char:GetData("SID"), 2)

							if #inv <= #freeSlots then
								local queries = {}

								for k, v in ipairs(inv) do
									table.insert(queries, {
										query = "UPDATE inventory SET name = ?, slot = ? WHERE name = ? AND slot = ?", 
										values = {
											string.format("%s-%s", char:GetData("SID"), 2),
											freeSlots[k],
											string.format("%s-%s", char:GetData("SID"), 1),
											v.Slot
										}
									})
								end

								MySQL.transaction.await(queries)
								refreshShit(char:GetData("SID"))

								Execute:Client(source, "Notification", "Success", "Retreived Items")
							else
								Execute:Client(source, "Notification", "Error", "Not Enough Slots Available")
							end
						else
							Execute:Client(source, "Notification", "Error", "No Items To Retreive")
						end
					end
					
					p:resolve(true)
				end
				Citizen.Await(p)
			end)
		end,
		Take = function(self, source)
			CreateThread(function()
				local p = promise.new()
				local plyr = Fetch:Source(source)
				if plyr ~= nil then
					local char = plyr:GetData("Character")
					if char ~= nil then
						local inv = getInventory(source, char:GetData("SID"), 2)

						if #inv > 0 then
							local freeSlots = Inventory:GetFreeSlotNumbers(char:GetData("SID"), 1)

							if #inv <= #freeSlots then
								local queries = {}

								for k, v in ipairs(inv) do
									table.insert(queries, {
										query = "UPDATE inventory SET name = ?, slot = ? WHERE name = ? AND slot = ?", 
										values = {
											string.format("%s-%s", char:GetData("SID"), 1),
											freeSlots[k],
											string.format("%s-%s", char:GetData("SID"), 2),
											v.Slot
										}
									})
								end

								MySQL.transaction.await(queries)
								refreshShit(char:GetData("SID"), true)

								Execute:Client(source, "Notification", "Success", "Retreived Items")
							else
								Execute:Client(source, "Notification", "Error", "Not Enough Slots Available")
							end
						else
							Execute:Client(source, "Notification", "Error", "No Items To Retreive")
						end
					end
					
					p:resolve(true)
				end
				Citizen.Await(p)
			end)
		end,
	},
	Container = {
		Open = function(self, src, item, identifier)
			Callbacks:ClientCallback(src, "Inventory:Container:Open", {
				item = item,
				container = ("container:%s"):format(identifier),
			}, function()
				Inventory:OpenSecondary(src, itemsDatabase[item.Name].container, ("container:%s"):format(identifier))
			end)
		end,
	},
	Stash = {
		Open = function(self, src, invType, identifier)
			Inventory:OpenSecondary(src, invType, ("stash:%s"):format(identifier))
		end,
	},
	Shop = {
		Open = function(self, src, identifier)
			Inventory:OpenSecondary(src, 11, ("shop:%s"):format(identifier))
		end,
	},
	Search = {
		Character = function(self, src, tSrc, id)
			Callbacks:ClientCallback(tSrc, "Inventory:ForceClose", {}, function(state)
				Execute:Client(tSrc, "Notification", "Info", "You Were Searched")
				Inventory:OpenSecondary(src, 1, id)
			end)
		end,
	},
	Rob = function(self, src, tSrc, id)
		Callbacks:ClientCallback(tSrc, "Inventory:ForceClose", {}, function(state)
			Inventory:OpenSecondary(src, 1, id)
		end)
	end,
	Poly = {
		Create = function(self, data)
			table.insert(_polyInvs, data.id)
			GlobalState[string.format("Inventory:%s", data.id)] = data
		end,
		-- Add = {
		-- 	Box = function(self, id, coords, length, width, options, entityId, restrictions)

		-- 	end,
		-- 	Poly = function(self) end,
		-- 	Circle = function(self) end,
		-- },
		Remove = function(self, id)

		end,
	},
	IsOpen = function(self, invType, id)
		return _openInvs[string.format("%s-%s", invType, id)]
	end,
}

_LOOT = {
	ItemClass = function(self, owner, invType, class, count)
		return Inventory:AddItem(owner, itemClasses[class][math.random(#itemClasses[class])], count, {}, invType)
	end,
	CustomSet = function(self, set, owner, invType, count)
		return Inventory:AddItem(owner, set[math.random(#set)], count, {}, invType)
	end,
	CustomSetWithCount = function(self, set, owner, invType)
		local i = set[math.random(#set)]
		return Inventory:AddItem(owner, i.name, math.random(i.min or 0, i.max), {}, invType)
	end,
	-- Pass a set array with the following layout
	-- set = {
	-- 	{chance_num, item_name },
	-- }
	CustomWeightedSet = function(self, set, owner, invType)
		local randomItem = Utils:WeightedRandom(set)
		if randomItem then
			return Inventory:AddItem(owner, randomItem, 1, {}, invType)
		end
	end,
	-- Pass a set array with the following layout
	-- set = {
	-- 	{chance_num, { name = item, max = max } },
	-- }
	CustomWeightedSetWithCount = function(self, set, owner, invType, dontAdd)
		local randomItem = Utils:WeightedRandom(set)
		if randomItem?.name and randomItem?.max then
			if dontAdd then
				return {
					name = randomItem.name,
					count = math.random(randomItem.min or 1, randomItem.max)
				}
			else
				return Inventory:AddItem(owner, randomItem.name, math.random(randomItem.min or 1, randomItem.max), randomItem.metadata or {}, invType)
			end
		end
	end,
	-- Pass a set array with the following layout
	-- set = {
	-- 	{chance_num, { name = item, max = max } },
	-- }
	CustomWeightedSetWithCountAndModifier = function(self, set, owner, invType, modifier, dontAdd)
		local randomItem = Utils:WeightedRandom(set)
		if randomItem?.name and randomItem?.max then
			if dontAdd then
				return {
					name = randomItem.name,
					count = math.random(randomItem.min or 1, randomItem.max) * modifier
				}
			else
				return Inventory:AddItem(owner, randomItem.name, math.random(randomItem.min or 1, randomItem.max) * modifier, randomItem.metadata or {}, invType)
			end
		end
	end,
	Sets = {
		Gem = function(self, owner, invType)
			local randomGem = Utils:WeightedRandom({
				{8, "diamond"},
				{5, "emerald"},
				{10, "sapphire"},
				{12, "ruby"},
				{16, "amethyst"},
				{18, "citrine"},
				{31, "opal"},
			})
			return Inventory:AddItem(owner, randomGem, 1, {}, invType)
		end,
		Ore = function(self, owner, invType, count)
			local randomOre = Utils:WeightedRandom({
				{18, "goldore"},
				{27, "silverore"},
				{55, "ironore"},
			})
			return Inventory:AddItem(owner, randomOre, count, {}, invType)
		end,
	},
}

WEAPONS = {
	IsEligible = function(self, source)
		local char = Fetch:Source(source):GetData("Character")
		local licenses = char:GetData("Licenses")
		if licenses ~= nil and licenses.Weapons ~= nil then
			return licenses.Weapons.Active
		else
			return false
		end
	end,
	Save = function(self, source, id, ammo, clip)
		local char = Fetch:Source(source):GetData("Character")
		Inventory:UpdateMetaData(id, {
			ammo = ammo,
			clip = clip,
		})
	end,
	Purchase = function(self, sid, item, isScratched, isCompanyOwned)
		local p = promise.new()

		if not isCompanyOwned then
			local plyr = Fetch:SID(sid)
			if plyr ~= nil then
				local char = plyr:GetData("Character")
				if char ~= nil then
					local hash = GetHashKey(item.name)
					local sn = string.format("SA-%s-%s", math.abs(hash), Sequence:Get(item.name))
					local model = nil
					if itemsDatabase[item.name] then
						model = itemsDatabase[item.name].label
					end
	
					if isScratched == nil then
						isScratched = false
					end
	
					Database.Game:insertOne({
						collection = "firearms",
						document = {
							Serial = sn,
							Item = item.name,
							Model = model,
							Owner = {
								Char = char:GetData("ID"),
								SID = char:GetData("SID"),
								First = char:GetData("First"),
								Last = char:GetData("Last"),
							},
							PurchaseTime = (os.time() * 1000),
							Scratched = isScratched,
						},
					}, function(success)
						p:resolve(true)
					end)
	
					Citizen.Await(p)
					return sn
				end
			end
		else
			local hash = GetHashKey(item.name)
			local sn = string.format("SA-%s-%s", math.abs(hash), Sequence:Get(item.name))
			local model = nil
			if itemsDatabase[item.name] then
				model = itemsDatabase[item.name].label
			end

			if isScratched == nil then
				isScratched = false
			end

			local flags = nil
			if isCompanyOwned.stolen then
				flags = {
					{
						Date = os.time() * 1000,
						Type = "stolen",
						Description = "Stolen In Armed Robbery"
					}
				}
			end

			Database.Game:insertOne({
				collection = "firearms",
				document = {
					Serial = sn,
					Item = item.name,
					Model = model,
					Owner = {
						Company = isCompanyOwned.name,
					},
					PurchaseTime = (os.time() * 1000),
					Scratched = isScratched,
				},
			}, function(success)
				p:resolve(true)
			end)

			Citizen.Await(p)
			return sn
		end
	end,
	GetComponentItem = function(self, type, component)
		for k, v in pairs(itemsDatabase) do
			if v.component ~= nil and v.component.type == type and v.component.string == component then
				return v.name
			end
		end
		return nil
	end,
	EquipAttachment = function(self, source, item)
		local plyr = Fetch:Source(source)
		if plyr ~= nil then
			local char = plyr:GetData("Character")
			if char ~= nil then
				local p = promise.new()
				Callbacks:ClientCallback(source, "Weapons:Check", {}, function(data)
					if not data then
						Execute:Client(source, "Notification", "Error", "No Weapon Equipped")
						p:resolve(false)
					else
						local itemData = Inventory.Items:GetData(item.Name)
						local weaponData = Inventory.Items:GetData(data.item)
						if itemData ~= nil and itemData.component ~= nil then
							if itemData.component.strings[weaponData.weapon or weaponData.name] ~= nil then
								Callbacks:ClientCallback(
									source,
									"Weapons:EquipAttachment",
									itemData.label,
									function(notCancelled)
										if notCancelled then
											local slotData = Inventory:GetItem(data.id)

											if slotData ~= nil then
												slotData.MetaData = json.decode(slotData.MetaData or "{}")

												local unequipItem = nil
												local unequipCreated = nil
												if
													slotData.MetaData.WeaponComponents ~= nil
													and slotData.MetaData.WeaponComponents[itemData.component.type]
														~= nil
												then
													if
														slotData.MetaData.WeaponComponents[itemData.component.type].attachment
														== itemData.component.string
													then
														Execute:Client(
															source,
															"Notification",
															"Error",
															"Attachment Already Equipped"
														)
														return p:resolve(false)
													end
													unequipItem =
														slotData.MetaData.WeaponComponents[itemData.component.type].item
													unequipCreated =
														slotData.MetaData.WeaponComponents[itemData.component.type].created
												end
	
												local comps = table.copy(slotData.MetaData.WeaponComponents or {})
												comps[itemData.component.type] = {
													type = itemData.component.type,
													item = item.Name,
													created = item.CreateDate,
													attachment = itemData.component.strings[weaponData.weapon or weaponData.name],
												}
	
												Inventory.Items:RemoveSlot(item.Owner, item.Name, 1, item.Slot, 1)
												if unequipItem ~= nil then
													local returnData = Inventory.Items:GetData(unequipItem)
													if returnData?.component?.returnItem then
														Inventory:AddItem(item.Owner, unequipItem, 1, {}, 1, false, false, false, false, false, unequipCreated or os.time())
													end
												end
	
												Inventory:SetMetaDataKey(
													slotData.id,
													"WeaponComponents",
													comps
												)
	
												Wait(400)
	
												TriggerClientEvent("Weapons:Client:UpdateAttachments", source, comps)
	
												return p:resolve(true)
											else
												return p:resolve(false)
											end
											
										else
											return p:resolve(false)
										end
									end
								)
							else
								Execute:Client(source, "Notification", "Error", "This Does Not Fit On This Weapon")
								return p:resolve(false)
							end
						else
							Execute:Client(source, "Notification", "Error", "Something Was Not Defined")
							return p:resolve(false)
						end
					end
				end)

				return Citizen.Await(p)
			else
				return false
			end
		else
			return false
		end
	end,
	RemoveAttachment = function(self, source, slotId, attachment)
		local plyr = Fetch:Source(source)
		if plyr ~= nil then
			local char = plyr:GetData("Character")
			if char ~= nil then
				local slot = Inventory:GetSlot(char:GetData("SID"), slotId, 1)
				if slot ~= nil then
					if slot.MetaData.WeaponComponents ~= nil and slot.MetaData.WeaponComponents[attachment] ~= nil then
						local itemData = Inventory.Items:GetData(slot.MetaData.WeaponComponents[attachment].item)
						if itemData ~= nil then
							Inventory:AddItem(char:GetData("SID"), itemData.name, 1, {}, 1, false, false, false, false, false, slot.MetaData.WeaponComponents[attachment].created or os.time())
							slot.MetaData.WeaponComponents[attachment] = nil	
							Inventory:SetMetaDataKey(
								slot.id,
								"WeaponComponents",
								slot.MetaData.WeaponComponents
							)
							TriggerClientEvent("Weapons:Client:UpdateAttachments", source, slot.MetaData.WeaponComponents)
						end
					end
				end
			end
		end
	end,
}

-- this should be fine??
ENTITYTYPES = {
    Get = function(self, cb)
        Database.Game:find({
            collection = 'entitytypes',
            query = {
            
            }
        }, function(success, results)
            if not success then return; end
            cb(results)
        end)
    end,
    GetID = function(self, id, cb)
        cb(LoadedEntitys[id])
    end
}

AddEventHandler("Proxy:Shared:RegisterReady", function()
	exports["mythic-base"]:RegisterComponent("Crafting", CRAFTING)
    exports["mythic-base"]:RegisterComponent("Inventory", INVENTORY)
    exports["mythic-base"]:RegisterComponent("Loot", _LOOT)
    exports["mythic-base"]:RegisterComponent("Weapons", WEAPONS)
    exports['mythic-base']:RegisterComponent('EntityTypes', ENTITYTYPES)
end)