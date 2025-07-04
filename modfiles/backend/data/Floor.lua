local Object = require("backend.data.Object")
local Line = require("backend.data.Line")

---@alias LineObject Line | Floor
---@alias LineParent Factory | Floor

---@class Floor: Object, ObjectMethods
---@field class "Floor"
---@field parent LineParent
---@field next LineObject?
---@field previous LineObject?
---@field level integer
---@field first LineObject?
---@field products SimpleItem[]
---@field byproducts SimpleItem[]
---@field ingredients SimpleItem[]
---@field power number
---@field emissions number
---@field machine_count integer
local Floor = Object.methods()
Floor.__index = Floor
script.register_metatable("Floor", Floor)

---@param level integer
---@return Floor
local function init(level)
    local object = Object.init({
        level = level,
        first = nil,

        products = {},
        byproducts = {},
        ingredients = {},
        power = 0,
        emissions = 0,
        machine_count = 0
    }, "Floor", Floor)  --[[@as Floor]]
    return object
end


function Floor:index()
    OBJECT_INDEX[self.id] = self
    for line in self:iterator() do line:index() end
end


---@param line LineObject
---@param relative_object LineObject?
---@param direction NeighbourDirection?
function Floor:insert(line, relative_object, direction)
    line.parent = self
    self:_insert(line, relative_object, direction)
end

---@param line LineObject
---@param preserve boolean?
function Floor:remove(line, preserve)
    line.parent = nil
    self:_remove(line)

    if preserve then return end
    -- Convert floor to line in parent if only defining line remains
    if self.level > 1 and self.first.next == nil then
        self.parent:replace(self, self.first)
    end
end

---@param line LineObject
---@param new_line LineObject
function Floor:replace(line, new_line)
    new_line.parent = self
    self:_replace(line, new_line)
end


---@param line LineObject
---@param direction NeighbourDirection
---@param spots integer?
function Floor:shift(line, direction, spots)
    self:_shift(line, direction, spots)
end


---@return LineObject?
function Floor:find_last()
    return self:_find_last()  --[[@as LineObject?]]
end

---@param filter ObjectFilter?
---@param pivot LineObject?
---@param direction NeighbourDirection?
---@return fun(): LineObject?
function Floor:iterator(filter, pivot, direction)
    return self:_iterator(filter, pivot, direction)
end

---@param filter ObjectFilter?
---@param pivot LineObject?
---@param direction NeighbourDirection?
---@return number count
function Floor:count(filter, pivot, direction)
    return self:_count(filter, pivot, direction)
end


---@alias ComponentDataSet { proto: FPPrototype, amount: number }

---@class ComponentData
---@field machines { [string]: ComponentDataSet }
---@field modules { [string]: ComponentDataSet }

-- Returns the machines and modules needed to actually build this floor
---@param skip_done boolean
---@param component_table ComponentData?
---@return ComponentData components
function Floor:get_component_data(skip_done, component_table)
    local components = component_table or {machines={}, modules={}}

    local function add_component(table, proto, quality_proto, amount)
        local combined_name = proto.name .. "-" .. quality_proto.name
        local component = table[combined_name]
        if component == nil then
            table[combined_name] = {proto = proto, quality_proto = quality_proto, amount = amount}
        else
            component.amount = component.amount + amount
        end
    end

    local function add_machine(object, amount)
        if object.proto.built_by_item then
            add_component(components.machines, object.proto.built_by_item, object.quality_proto, amount)
        end

        for module in object.module_set:iterator() do
            add_component(components.modules, module.proto, module.quality_proto, amount * module.amount)
        end
    end

    for line in self:iterator() do
        if line.class == "Floor" then  ---@cast line Floor
            line:get_component_data(skip_done, components)

        elseif not skip_done or not line.done then
            local machine = line.machine
            local ceil_machine_count = math.ceil(machine.amount - 0.001)
            add_machine(machine, ceil_machine_count)

            local beacon = line.beacon
            if beacon and beacon.total_amount then
                local ceil_total_amount = math.ceil(beacon.total_amount - 0.001)
                add_machine(beacon, ceil_total_amount)
            end
        end
    end

    return components
end


---@param object LineObject
---@return boolean compatible
function Floor:check_product_compatibility(object)
    if self.level == 1 then return true end

    local relevant_line = (object.class == "Floor") and object.first or object
    -- The triple loop is crappy, but it's the simplest way to check
    for _, product in pairs(relevant_line.recipe_proto.products) do
        for line in self:iterator() do
            for _, ingredient in pairs(line.ingredients) do
                if ingredient.proto.type == product.type and ingredient.proto.name == product.name then
                    return true
                end
            end
        end
    end
    return false
end

function Floor:reset_surface_compatibility()
    for line in self:iterator() do
        if line.class == "Floor" then  ---@cast line Floor
            line:reset_surface_compatibility()
        else
            line.surface_compatibility = nil
        end
    end
end

---@param object CopyableObject
---@return boolean success
---@return string? error
function Floor:paste(object)
    if object.class == "Line" or object.class == "Floor" then
        ---@cast object LineObject
        if not self:check_product_compatibility(object) then
            return false, "recipe_irrelevant"  -- found no use for the recipe's products
        end

        self.parent:replace(self, object)
        return true, nil
    else
        return false, "incompatible_class"
    end
end


---@alias PackedLineObject PackedLine | PackedFloor

---@class PackedFloor: PackedObject
---@field class "Floor"
---@field level integer
---@field lines PackedLineObject[]?

---@return PackedFloor packed_self
function Floor:pack()
    return {
        class = self.class,
        level = self.level,
        lines = self:_pack()
    }
end

---@param packed_self PackedFloor
---@return Floor floor
local function unpack(packed_self)
    local unpacked_self = init(packed_self.level)

    local function unpacker(line) return (line.class == "Floor") and unpack(line) or Line.unpack(line) end
    unpacked_self.first = Object.unpack(packed_self.lines, unpacker, unpacked_self)  --[[@as LineObject]]

    return unpacked_self
end


---@return boolean valid
function Floor:validate()
    self.valid = self:_validate()
    return self.valid
end

---@param player LuaPlayer
---@return boolean success
function Floor:repair(player)
    local pivot = self.first
    if self.level > 1 and self.first and not self.first.valid then
        local line_valid = self.first:repair(player)
        -- If the defining line can't be repaired, the floor is dead
        if not line_valid then return false end
        pivot = self.first.next
    end

    if pivot then self:_repair(player, pivot) end
    self.valid = true

    return self.valid
end

return {init = init, unpack = unpack}
