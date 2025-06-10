AddEventHandler("Characters:Client:Updated", function(key)
	if key == "Cash" then
		TriggerServerEvent('Inventory:Cash', key)
	end
end)

-- TODO MYTHIC:

-- MYTHIC CODE TO LOOK AT FOR STATUS
if itemsDatabase[item.Name].statusChange.Add ~= nil then
    for k, v in pairs(itemsDatabase[item.Name].statusChange.Add) do
        TriggerClientEvent("Status:Client:updateStatus", source, k, true, v)
    end
end

if itemsDatabase[item.Name].statusChange.Remove ~= nil then
    for k, v in pairs(itemsDatabase[item.Name].statusChange.Remove) do
        TriggerClientEvent("Status:Client:updateStatus", source, k, false, -v)
    end
end


function client.setPlayerStatus(values)
    --TODO
end

-- TODO Convert all component functions to use ox inventory (its currently using mythic inventories default code as a placeholder)
_CRAFTING = {
	Benches = {
		Open = function(self, bench)
			Callbacks:ServerCallback("Crafting:GetBenchDetails", bench, function(results)
				if results == nil then
					return
				else
					LocalPlayer.state.craftingOpen = true
					SendNUIMessage({
						type = "SET_BENCH",
						data = {
							benchName = "Workbench",
							bench = bench,
							cooldowns = results.cooldowns,
							actionString = results.string,
							recipes = results.recipes,
							myCounts = results.myCounts,
						},
					})
					SendNUIMessage({
						type = "SET_MODE",
						data = {
							mode = "crafting",
						},
					})
					SetNuiFocus(true, true)
					SendNUIMessage({
						type = "APP_SHOW",
					})
				end
			end)
		end,
		Cleanup = function(self)
			for k, v in ipairs(_benchObjs) do
				Targeting:RemoveEntity(v)
				DeleteEntity(v)
			end
			_benchObjs = {}
		end,
		Refresh = function(self, interior)
			self:Cleanup()

			for k, v in ipairs(_benches) do
				if v.targeting and not v.targeting.manual then
					if
						v.restrictions.interior == nil
						or v.restrictions.interior
							== GlobalState[string.format("%s:Property", LocalPlayer.state.ID)]
					then
						local obj = nil
						if v.targeting.model ~= nil then
							obj = CreateObject(
								GetHashKey(v.targeting.model),
								v.location.x,
								v.location.y,
								v.location.z,
								false,
								true,
								false
							)
							FreezeEntityPosition(obj, true)
							table.insert(_benchObjs, obj)
							SetEntityHeading(obj, v.location.h)
						end

						if
							v.restrictions.shared
							or (v.restrictions.char ~= nil and v.restrictions.char == LocalPlayer.state.Character:GetData(
								"SID"
							))
							or (v.restrictions.job ~= nil and Jobs.Permissions:HasJob(
								v.restrictions.job.id,
								v.restrictions.job.workplace,
								v.restrictions.job.grade,
								false,
								false,
								v.restrictions.job.permissionKey or "JOB_CRAFTING"
							))
							or (
								v.restrictions.rep ~= nil
								and Reputation:GetLevel(v.restrictions.rep.id) >= v.restrictions.rep.level
							)
						then
							local menu = {
								{
									icon = v.targeting.icon,
									text = v.label,
									event = "Crafting:Client:OpenCrafting",
									data = v,
								},
							}

							if v.canUseSchematics then
								table.insert(menu, {
									icon = "clipboard-list",
									text = "Add Schematic To Bench",
									event = "Crafting:Client:AddSchematic",
									data = v,
									isEnabled = function(data, entityData)
										return Inventory.Items:HasType(17, 1)
									end,
								})
							end

							if v.restrictions.job ~= nil then
								menu.jobPerms = {
									{
										job = v.restrictions.job.id,
										workplace = v.restrictions.job.workplace,
										reqDuty = v.restrictions.job.onDuty,
									},
								}
							end

							if obj ~= nil then
								Targeting:AddEntity(obj, v.targeting.icon, menu)
							elseif v.targeting.ped ~= nil then
								PedInteraction:Add(
									v.id,
									GetHashKey(v.targeting.ped.model),
									vector3(v.location.x, v.location.y, v.location.z),
									v.location.h,
									25.0,
									menu,
									v.targeting.icon,
									v.targeting.ped.task
								)
							elseif v.targeting.poly ~= nil then
								Targeting.Zones:AddBox(
									v.id,
									v.targeting.icon,
									v.targeting.poly.coords,
									v.targeting.poly.w,
									v.targeting.poly.l,
									v.targeting.poly.options,
									menu,
									2.0,
									true
								)
							end
						end
					end
				end
			end
		end,
	},
}
_INVENTORY = {
	_required = { "IsEnabled", "Open", "Close", "Set", "Enable", "Disable", "Toggle", "Check" },
	IsEnabled = function(self)
		return _startup and not _disabled and not _openCd and not Hud:IsDisabled()
	end,
	Open = {
		Player = function(self, doSecondary)
			if Inventory:IsEnabled() then
				Phone:Close()
				Interaction:Hide()
				if not LocalPlayer.state.inventoryOpen then
					LocalPlayer.state.inventoryOpen = true
					TriggerServerEvent("Inventory:Server:Request", doSecondary and SecondInventory or false)
				end
			end
		end,
		Secondary = function(self)
			SendNUIMessage({
				type = "SHOW_SECONDARY_INVENTORY",
			})
		end,
	},
	Close = {
		All = function(self)
			SendNUIMessage({
				type = "APP_HIDE",
			})
			SetNuiFocus(false, false)

			LocalPlayer.state.inventoryOpen = false
			LocalPlayer.state.craftingOpen = false
			Inventory.Set.Player.Data.Open = false

			if trunkOpen and trunkOpen > 0 then
				PlayTrunkCloseAnim()
				Wait(900)
				Vehicles.Sync.Doors:Shut(trunkOpen, 5, false)
				trunkOpen = false
				ClearPedTasks(PlayerPedId())
			end

			if Inventory.Set.Secondary.Data.Open then
				Inventory.Close:Secondary()
			end
		end,
		Secondary = function(self)
			if trunkOpen and trunkOpen > 0 then
				PlayTrunkCloseAnim()
				Wait(900)
				Vehicles.Sync.Doors:Shut(trunkOpen, 5, false)
				trunkOpen = false
				ClearPedTasks(PlayerPedId())
			end

			if Inventory.Set.Secondary.Data.Open then
				Callbacks:ServerCallback("Inventory:CloseSecondary", SecondInventory, function()
					SecondInventory = {}
					_container = nil
					Inventory.Set.Secondary.Data.Open = false
				end)
			end
		end,
	},
	Set = {
		Player = {
			Data = {
				allowOpen = true,
				Open = false,
			},
			Inventory = function(self, data)
				if not data then
					LocalPlayer.state.inventoryOpen = false
					LocalPlayer.state.craftingOpen = false
					Inventory.Set.Player.Data.Open = false
					return
				end
				SendNUIMessage({
					type = "SET_PLAYER_INVENTORY",
					data = data,
				})
			end,
			Slot = function(self, slot)
				SendNUIMessage({
					type = "SET_PLAYER_SLOT",
					data = {
						slot = slot,
					},
				})
			end,
		},
		Secondary = {
			Data = {
				Open = false,
			},
			Inventory = function(self, data)
				Inventory.Set.Secondary.Data.Open = true
				SendNUIMessage({
					type = "SET_SECONDARY_INVENTORY",
					data = data,
				})
			end,
			Slot = function(self, slot)
				SendNUIMessage({
					type = "SET_SECONDARY_SLOT",
					data = {
						slot = slot,
					},
				})
			end,
		},
	},
	Used = {
		HotKey = function(self, control)
			if not _hkCd and not _inUse and not Hud:IsDisabled() then
				SendNUIMessage({
					type = "USE_ITEM_PLAYER",
					data = {
						originSlot = control,
					},
				})
				_hkCd = true
				Callbacks:ServerCallback("Inventory:UseSlot", { slot = control }, function(state)
					if not state then
						SendNUIMessage({
							type = "SLOT_NOT_USED",
							data = {
								originSlot = control,
							},
						})
					end

					SetTimeout(3000, function()
						_hkCd = false
					end)
				end)
			end
		end,
	},
	-- ALL OF THIS NEEDS TO BE VALIDATED SERVER SIDE
	-- THIS IS BEING ADDED TO SAVE A CLIENT > SERVER > CLIENT CALL
	Items = {
		GetCount = function(self, item, bundleWeapons)
			local counts = Inventory.Items:GetCounts(bundleWeapons)
			return counts[item] or 0
		end,
		GetCounts = function(self, bundleWeapons)
			if _cachedInventory == nil or _cachedInventory.inventory == nil or #_cachedInventory.inventory == 0 then
				return {}
			end
			local counts = {}

			if LocalPlayer.state.Character == nil then
				return counts
			end

			for k, v in ipairs(_cachedInventory.inventory) do
				if
					_items[v.Name].durability == nil
					or not _items[v.Name].isDestroyed
					or (((v.CreateDate or 0) + _items[v.Name].durability) >= GetCloudTimeAsInt())
				then
					local itemData = Inventory.Items:GetData(v.Name)

					if bundleWeapons and itemData?.weapon then
						counts[itemData?.weapon] = (counts[itemData?.weapon] or 0) + v.Count
					end
					counts[v.Name] = (counts[v.Name] or 0) + v.Count
				end
			end

			return counts
		end,
		GetTypeCounts = function(self)
			local counts = {}

			if LocalPlayer.state.Character == nil or _cachedInventory == nil then
				return counts
			end

			for k, v in ipairs(_cachedInventory.inventory) do
				if
					_items[v.Name].durability == nil
					or not _items[v.Name].isDestroyed
					or (((v.CreateDate or 0) + _items[v.Name].durability) >= GetCloudTimeAsInt())
				then
					local itemData = Inventory.Items:GetData(v.Name)
					counts[itemData.type] = (counts[itemData.type] or 0) + v.Count
				end
			end

			return counts
		end,
		Has = function(self, item, count, bundleWeapons)
			return Inventory.Items:GetCount(item, bundleWeapons) >= count
		end,
		HasType = function(self, itemType, count)
			return (Inventory.Items:GetTypeCounts()[itemType] or 0) >= count
		end,
		GetData = function(self, name)
			if name ~= nil then
				return _items[name]
			else
				return _items
			end
		end,
		GetWithStaticMetadata = function(self, masterKey, mainIdName, textureIdName, gender, data)
			for k, v in pairs(_items) do
				if
					v.staticMetadata ~= nil
					and v.staticMetadata[masterKey] ~= nil
					and v.staticMetadata[masterKey][gender][mainIdName] == data[mainIdName]
					and v.staticMetadata[masterKey][gender][textureIdName] == data[textureIdName]
				then
					return k
				end
			end

			return nil
		end,
	},
	Check = {
		Player = {
			HasItem = function(self, item, count)
				return Inventory.Items:Has(item, count)
			end,
			HasItems = function(self, items)
				for k, v in ipairs(items) do
					if not Inventory.Items:Has(v.item, v.count, true) then
						return false
					end
				end
				return true
			end,
			HasAnyItems = function(self, items)
				for k, v in ipairs(items) do
					if Inventory.Items:Has(v.item, v.count) then
						return true
					end
				end

				return false
			end,
		},
	},
	Enable = function(self)
		_disabled = false
	end,
	Disable = function(self)
		_disabled = true
	end,
	Toggle = function(self)
		_disabled = not _disabled
	end,
	Dumbfuck = {
		Open = function(self, data)
			Callbacks:ServerCallback("Inventory:Server:Open", data, function(state)
				if state then
					SecondInventory = { invType = data.invType, owner = data.owner }
				end
			end)
		end,
	},
	Stash = {
		Open = function(self, type, identifier)
			Callbacks:ServerCallback("Stash:Server:Open", {
				type = type,
				identifier = identifier,
			}, function(state)
				if state ~= nil then
					SecondInventory = state
				end
			end)
		end,
	},
	Shop = {
		Open = function(self, identifier)
			Callbacks:ServerCallback("Shop:Server:Open", {
				identifier = identifier,
			}, function(state)
				if state then
					SecondInventory = { invType = state, owner = string.format("shop:%s", identifier) }
				end
			end)
		end,
	},
	Search = {
		Character = function(self, serverId)
			Callbacks:ServerCallback("Inventory:Search", {
				serverId = serverId,
			}, function(owner)
				if owner then
					SecondInventory = { invType = 1, owner = owner }
				end
			end)
		end,
	},
	StaticTooltip = {
		Open = function(self, item)
			SendNUIMessage({
				type = "OPEN_STATIC_TOOLTIP",
				data = {
					item = item,
				}
			})
		end,
		Close = function(self)
			SendNUIMessage({
				type = "CLOSE_STATIC_TOOLTIP",
			})
		end,
	}
}
_WEAPONS = {
	GetEquippedHash = function(self)
		if _equipped ~= nil then
			return GetHashKey(_items[_equipped.Name].weapon or _equipped.Name)
		else
			return nil
		end
	end,
	GetEquippedItem = function(self)
		return _equipped
	end,
	IsEligible = function(self)
		local licenses = LocalPlayer.state.Character:GetData("Licenses")
		if licenses ~= nil and licenses.Weapons ~= nil then
			return licenses.Weapons.Active
		else
			return false
		end
	end,
	Equip = function(self, item)
		local ped = PlayerPedId()
		local hash = GetHashKey(_items[item.Name].weapon or item.Name)
		local itemData = _items[item.Name]

		-- print(string.format("Equipping Weapon, Total Ammo: %s, Clip: %s", item.MetaData.ammo or 0, item.MetaData.clip or 0))
		if LocalPlayer.state.onDuty == "police" then
			if _equipped ~= nil then
				Weapons:Unequip(_equipped)
			end
			anims.Cop:Draw(ped, hash, GetHashKey(itemData.ammoType), item.MetaData.ammo or 0, item.MetaData.clip or 0, item, itemData)
		else
			if _equipped ~= nil then
				Weapons:Unequip(_equipped)
			end
			anims.Draw:OH(ped, hash, GetHashKey(itemData.ammoType), item.MetaData.ammo or 0, item.MetaData.clip or 0, item, itemData)
		end

		_equipped = item
		_equippedData = itemData
		TriggerEvent("Weapons:Client:SwitchedWeapon", _equipped.Name, _equipped, _items[_equipped.Name])

		SendNUIMessage({
			type = "SET_EQUIPPED",
			data = {
				item = _equipped,
			}
		})

		RunDegenThread()
	end,
	UnequipIfEquipped = function(self)
		if _equipped ~= nil then
			Weapons:Unequip(_equipped)
			TriggerEvent('Weapons:Client:Attach')
		end
	end,
	UnequipIfEquippedNoAnim = function(self)
		if _equipped ~= nil then
			local ped = PlayerPedId()
			local itemData = _items[_equipped.Name]
			UpdateAmmo(_equipped, diff)
			SetPedAmmoByType(ped, GetHashKey(itemData.ammoType), 0)
			SetCurrentPedWeapon(ped, GetHashKey("WEAPON_UNARMED"), true)
			RemoveAllPedWeapons(ped)
			_equipped = nil
			_equippedData = nil
			TriggerEvent("Weapons:Client:SwitchedWeapon", false)
			SendNUIMessage({
				type = "SET_EQUIPPED",
				data = {
					item = _equipped,
				}
			})
			TriggerEvent('Weapons:Client:Attach')
		end
	end,
	Unequip = function(self, item, diff)
		if item == nil then
			return
		end
		local ped = PlayerPedId()
		local hash = GetHashKey(_items[item.Name].weapon or item.Name)
		local itemData = _items[item.Name]
		UpdateAmmo(item, diff)
		if LocalPlayer.state.onDuty == "police" then
			anims.Cop:Holster(ped)
		else
			anims.Holster:OH(ped)
		end

		SetPedAmmoByType(ped, GetHashKey(itemData.ammoType), 0)

		if item.MetaData.WeaponComponents ~= nil then
			for k, v in pairs(item.MetaData.WeaponComponents) do
				RemoveWeaponComponentFromPed(ped, hash, v.attachment)
			end
		end

		_equipped = nil
		_equippedData = nil
		TriggerEvent("Weapons:Client:SwitchedWeapon", false)
		SendNUIMessage({
			type = "SET_EQUIPPED",
			data = {
				item = _equipped,
			}
		})
	end,
	Ammo = {
		Add = function(self, item)
			if _equipped ~= nil then
				local ped = PlayerPedId()
				local hash = GetHashKey(_items[_equipped.Name].weapon or _equipped.Name)
				AddAmmoToPed(ped, hash, item.bulletCount or 10)
			end
		end,
	},
}

AddEventHandler("Proxy:Shared:RegisterReady", function()
	exports["mythic-base"]:RegisterComponent("Crafting", _CRAFTING)
    exports["mythic-base"]:RegisterComponent("Inventory", _INVENTORY)
    exports["mythic-base"]:RegisterComponent("Weapons", _WEAPONS)
end)
